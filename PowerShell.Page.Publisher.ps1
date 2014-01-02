#
# PowerShell.Page.Publisher.ps1 written by Tridion.Zen
#
$MAX_DAYS = 7   # republish pages older than 5 days
#
$tcm = get-content "PATH\CONFIG_URL.TXT" # e.g. textfile with the CMS CoreService URL: http://SERVER/webservices/coreservice2011.svc 
$uid = get-content "PATH\CONFIG_UID.TXT" # e.g. textfile with the Tridion user using the CoreService: DOMAIN\USERNAME 
$pwd = get-content "PATH\CONFIG_PWD.TXT" # e.g. textfile with the password for the Tridion user using the CoreService: "Passw0rd!"
#
cls
write-host "Wait.....!"
$encryptedPass = convertto-securestring $pwd -asplaintext -force
$creds = new-object system.management.automation.pscredential($uid, $encryptedPass)
$client = new-webserviceproxy -uri $tcm -namespace tcm -class core -credential $creds
write-host "Client   |" $client.url
try {
    write-host "Version  |" $client.getapiversion()
    write-host "User     |" $client.getcurrentuser().title
} catch {
    write-host "Problem  |" $_
    $client.dispose()
    $client = $null
    $creds = $null
    return
}
#
# start of functions
function displayTargets ($targets) {
    write-host "`nTargets  | " -nonewline
    $targets | % {
        $targetName = $client.read($_, $null)
        write-host $_ "" -nonewline 
	$title = $targetName.title
        write-host $title -nonewline -backgroundcolor white -foregroundcolor blue
        write-host " | " -nonewline
    }
    return $title
}
function displayGroups ($groups) {
    write-host "`nStruct Gr| " -nonewline
    $groups | % {
        $groupName = $client.read($_, $null)
        write-host $_ "" -nonewline
        write-host $groupName.title -nonewline -backgroundcolor white -foregroundcolor blue
        write-host " | " -nonewline
    }
    write-host
}
# end of functions
#
$liveTarTitle = ""
$liveTargets = @("tcm:0-116-65538") # e.g. one or more targets, note the 65538 id
$liveSGs = @("tcm:87-1-4") # e.g. one or more structure groups
$livePages = @() # e.g. one or more pages
$liveTarTitle = displayTargets $liveTargets
displayGroups  $liveSGs
#
$stagingTarTitle = ""
$stagingTargets = @() # idem, target for the staging site
$stagingSGs = @()
$stagingPages = @()
$stagingTarTitle = displayTargets $stagingTargets
displayGroups  $stagingSGs
#
$publishInstruction = new-object tcm.publishinstructiondata
$publishInstruction.maximumnumberofrenderfailures = 777
$publishInstruction.maximumnumberofrenderfailuresspecified = $true
$publishInstruction.rollbackonfailure = $false
$publishInstruction.rollbackonfailurespecified = $true
$publishInstruction.renderinstruction  = new-object tcm.renderinstructiondata -property @{ rendermode = "Publish"; rendermodespecified = $true }
$publishInstruction.resolveinstruction = new-object tcm.resolveinstructiondata
$readOptions = new-object tcm.ReadOptions
#  
$pageFilter  = new-object tcm.OrganizationalItemItemsFilterData -property @{ itemtypes = "Page" }
$groupFilter = new-object tcm.OrganizationalItemItemsFilterData -property @{ itemtypes = "StructureGroup" }
#
# start of functions
function listItems ($source, $filter) {
    $xml = [xml] ($client.getlistxml($source, $filter).outerxml)
    $xml.listitems.item
}
function doPublishAndWait ($targets, $page) {
    $result = $client.publish(@($page.id), $publishInstruction, $targets, "Low", $true, $null)
    write-host "Wait" -nonewline
    for ($w = 0; $w -le 10; $w++) { write-host "." -nonewline; start-sleep -m 100 }
    for ($sleep=0; $sleep -le 10; $sleep++) { # after putting one page in the queue, wait for some time to allow other to publish, or to let Tridion do its work...
        write-host "`b-" -nonewline; start-sleep -m 100
        write-host "`b\" -nonewline; start-sleep -m 100
        write-host "`b|" -nonewline; start-sleep -m 100
        write-host "`b/" -nonewline; start-sleep -m 100
        write-host "`b-" -nonewline; start-sleep -m 100
        write-host "`b\" -nonewline; start-sleep -m 100
        write-host "`b|" -nonewline; start-sleep -m 100
        write-host "`b/" -nonewline; start-sleep -m 100
    }
    write-host "`b."
}
function doPublish ($targets, $title, $page) {
    if ($skipTest) { # publish allways...
        $script:cnt +=1
        write-host "Publish: " $cnt "| " -nonewline
        write-host $page.title -nonewline -foregroundcolor cyan
        write-host " | " -nonewline
        doPublishAndWait $targets $page 
        
    } else { # check and publish only pages which are not published recently
        write-host "Published? " -nonewline
        write-host $page.title "" -nonewline -foregroundcolor cyan
        $tooOld = $true
        $tooOldDate = "<<no set>>"
        $publishInfo = $client.GetListPublishInfo($page.id)
        $publishInfo | % {
            $delta = $now.date - $_.publishedat.date
		    $target = $_.publicationtarget.title 	                                   
            if ($title -eq $target) {
                if ($tooOld -and ($delta.totaldays -lt $MAX_DAYS)) { 
                    $tooOld = $false;
                    $tooOldDate = $_.publishedat
                }
            }              
            write-host $target $_.publishedat "| " -nonewline
        }
        if (!$tooOld -and $publishInfo) { 
            write-host "Is already published @ $tooOldDate" -foregroundcolor green
        } else { 
            write-host "Will be (re)published" -foregroundcolor yellow
            doPublishAndWait $targets $page
        }        
    }
}
function subPages ($targets, $title, $groups) {
    if ($groups.count -eq 0) { return }
    $group = $groups[$index]
    write-host "Str Group|" $index "of" $groups.length "| " -nonewline
    write-host $client.read($group, $null).title -nonewline -foregroundcolor magenta    
    write-host " | " -nonewline 
    write-host $title -nonewline -foregroundcolor magenta     
    write-host " | " -nonewline 
    write-host $now.date -foregroundcolor magenta    
    #
    $pages = listItems $group $pageFilter
    if ($pages.count) {
        write-host "Pages    |" $pages.count "| " -nonewline    
        $pages | % { 
            write-host $_.title -nonewline -foregroundcolor cyan
            write-host " | " -nonewline
        } 
        write-host
        $pages | % { doPublish $targets $title $_ }
    } elseif ($pages.id) {
        write-host "Page     |" $pages.title "| " -nonewline
        doPublish $targets $title $pages
    } else {
        write-host "Empty!"
    }    
}
function main ($targets, $title, $groups, $recursive) {
    $index = 0
    $now = get-date
    do {
        subPages $targets $title $groups
        if ($recursive) {
            $group = $groups[$index]
            listItems $group $groupFilter | % {
                if ($_.id) { $groups += $_.id }
            }
        }
        $index++
    } while ($index -lt $groups.length)
}
function mainSGs ($targets, $title, $groups) {
    main $targets $title $groups $true
}
function mainPages ($targets, $title, $groups) {
    main $targets $title $groups $false
}
#
$skipTest = $false # when False use MAX_DAYS to determine what to publish, when True publish always
$cnt = 0 
write-host
# uncomment the lines of code below
#mainPages $stagingTargets $stagingTarTitle $stagingPages
#mainPages $liveTargets    $liveTarTitle    $livePages
#mainSGs $stagingTargets $stagingTarTitle $stagingSGs
mainSGs $liveTargets    $liveTarTitle     $liveSGs
#
# end of script
$client.dispose()
$client = $null
