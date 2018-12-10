$createdByLabel = "CreatedBy";
$eventsstarttime = (Get-Date).AddDays(-89);
$azureCredential = Get-AutomationPSCredential -Name "vmtagtest"

if($azureCredential -ne $null)
{
	Write-Output "Attempting to authenticate as: [$($azureCredential.UserName)]"
}
else
{
   throw "No automation credential name was specified..."
}

Login-AzureRmAccount -Credential $azureCredential

function setTag 
{ 
    param ([string]$caller, $vM) 
    $newTags = $vM.Tags + @{ $createdByLabel = $caller }; 
    Set-AzureRmResource -Tag $newTags -ResourceId $vM.Id -Force | Out-Null; 
}

# Tag VMs for all subscriptions the user has access to with the Createdby lable above and the creator username if found
$subs = Get-AzureRmSubscription
#Loop through each Azure subscription user has access to
foreach ($sub in $subs) {
   
   $subID = $sub.SubscriptionId
   $subName = $sub.Name
   Select-AzureRmSubscription -SubscriptionId $subID
   if ($sub.Name -ne "Access to Azure Active Directory") { # There is no VMs in Access to Azure Active Directory subscriptions
      #Set-AzureRmContext -SubscriptionId $sub.id | Out-Null
      #Select-AzureRmSubscription -SubscriptionId $sub.id
      Write-Host "Collecting the VMs info for $subname"
      Write-Host ""
      Try {
            #############################################################################################################################
            #### Here we are getting all VMs for this Subscription
            #############################################################################################################################
            $Current = Get-AzureRmVm | Select-Object -Property @{Name = 'SubscriptionName'; Expression = {$sub.name}}, @{Name = 'SubscriptionID'; Expression = {$sub.id}}, Name, @{Label="Creator";Expression={$_.Tags["CreatedBy"]}}, @{Label="VmSize";Expression={$_.HardwareProfile.VmSize}}, @{Label="OsType";Expression={$_.StorageProfile.OsDisk.OsType}}, Location, VmId, ResourceGroupName, Id
      } 
      Catch {
            Write-Output "Failed to collect the VMs for $subname"
      }
      
      #Now we need the person who created the VM
      Foreach ($AzureVM in $Current) {
         #If the VM is not Taged with CreatedBy, we will set it.
         if (!$AzureVM.Creator) {
            write-host " No CreatedBy Tag found for the VM : " $AzureVM.Name -ForegroundColor Red
            $events = Get-AzureRmLog -ResourceId $AzureVM.Id -StartTime $eventsstarttime -WarningAction SilentlyContinue | Sort-Object -Property EventTimestamp;
            if ($events.Count -gt 0) 
            {
               Write-Host " I've found some Activity log events for the VM : " $AzureVM.Name -ForegroundColor Yellow
               $location = 0; 
               $entityOnly = $true; 
               foreach($event in $events) 
               { 
                  if($event[$location].Caller -like "*@*") 
                  {
                        Write-Host " you have good luck, a creator is found in the logs "  $events[$location].Caller -ForegroundColor Green
                        setTag -caller $events[$location].Caller -vM $AzureVM;
                        Write-Host " I've set the " $createdByLabel " Tag of the VM : " $AzureVM.Name " to " $events[$location].Caller -ForegroundColor Blue -BackgroundColor Yellow
                        $entityOnly = $false; 
                        break
                  } 
               }
               if ($entityOnly -eq $true) 
               { 
               Write-Host " Human creator not available, going with entity..." -ForegroundColor Yellow
               setTag -caller $events[0].Caller -vM $AzureVM; 
               } 
            }
            else {
               Write-Host " No creator information available, probably this VM was created over 90 days ago..." -ForegroundColor Red
               setTag -caller "Creator is Unknown" -vM $AzureVM; 
            }
         } 
         else 
         {
            Write-Host "Creator Tag was found : " $AzureVM.Creator -ForegroundColor Blue -BackgroundColor Black 
         }  
      }
   }
}