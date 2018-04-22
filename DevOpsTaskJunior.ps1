Configuration TargetTest{

	$LogFile = 'C:\myscript.txt'
    $Net452link = "https://download.microsoft.com/download/B/4/1/B4119C11-0423-477B-80EE-7A474314B347/NDP452-KB2901954-Web.exe"
    $AppZipLink = "https://github.com/TargetProcess/DevOpsTaskJunior/archive/master.zip"
	$ZipLoc =  "$env:SystemRoot\Temp\master.zip"
	$Net452Loc = "$env:SystemRoot\Temp\fr45.exe"
	$SlackCh = "https://hooks.slack.com/services/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"
	$hashNet452 = '6C2C589132E830A185C5F40F82042BEE3022E721A216680BD9B3995BA86F3781'
	$hashZip ='D45D11FE4CF2888093FF26E341F8818819BF524682AE93979316764D5A1A4626'
	$SiteLoc = "C:\inetpub\wwwroot\DevOpsTaskJunior-master"


    
    Node "localhost"{

    LocalConfigurationManager{
            RebootNodeIfNeeded = $true
            ConfigurationMode = 'ApplyAndAutoCorrect'
        }
		
		
        WindowsFeature IIS{
            Name = "Web-Server"
            Ensure = "Present"
        }
			
			
        WindowsFeature Net45{
            Name = "Web-Asp-Net45"
            Ensure = "Present"
        } 

		
        Script DownloadNet4.5.2{
            SetScript= {
				if ([System.IO.File]::Exists($using:Net452Loc) -ne $true -or (Get-FileHash $using:Net452Loc | %{$_ -match $using:hashNet452}) -ne $true )
			{
                    try{ 
						[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
						$client = New-Object System.Net.WebClient
						$client.DownloadFile( $using:Net452link, $using:Net452Loc)
						Start-Process -FilePath $using:Net452Loc -ArgumentList "/q /norestart" -Wait -NoNewWindow
						$global:DSCMachineStatus = 1					
                    }
                    catch{
						$exception = $_.Exception.Message
						Out-File -FilePath $using:LogFile -Append -InputObject "$(Get-Date -Format g) [Script]DownloadNet4.5.2  $exception"
						Write-Error "$_.Exception.Message" 
                    }
            }
			}
			
             TestScript = { 
				Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | %{$_ -match '379893'} 
				}
				
             GetScript = {
                if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | %{$_ -match '379893'})
                {
                    $NetBuildVersion =  (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
                    return $NetBuildVersion
                }
                else
                {
                    return ".Net 4.5.2 not found"
                }  
              }
              DependsOn = "[WindowsFeature]Net45"
              }


        Script DownloadZip{
            SetScript = {
				try{
					[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
					$client = New-Object System.Net.WebClient
					$client.DownloadFile($using:AppZipLink, $using:ZipLoc)}      
				catch{
					$exception = $_.Exception.Message
					Out-File -FilePath $using:LogFile -Append -InputObject "$(Get-Date -Format g) [Script]DownloadZip  $exception"
					Write-Error "$_.Exception.Message"
				}}

            TestScript = {
				if([System.IO.File]::Exists($using:ZipLoc))
            {
				if(Get-FileHash $using:ZipLoc | %{$_ -match $using:hashZip})
					{return $true}
				else
					{return $false}}
				else
					{return $false}
            }

            GetScript = {
                if (Get-FileHash $using:ZipLoc | %{$_ -match $using:hashZip})
                {
                    return "File exist"
                }
                else
                {
                    return "File Not exist"
                }}
				
            DependsOn = "[Script]DownloadNet4.5.2"
                }
        
                    
        Archive TargetZip{       
			Path = $ZipLoc
			Destination = "C:\inetpub\wwwroot\"
			DependsOn = "[Script]DownloadZip"
        }
		
		
        Script FindError{
            SetScript = {
            try{
				(Get-Content "$using:SiteLoc\Web.config").Replace(".>",">") | Set-Content "$using:SiteLoc\Web.config"}
            catch{
				$exception = $_.Exception.Message
				Out-File -FilePath $using:LogFile -Append -InputObject "$(Get-Date -Format g) [Script]FindError  $exception"
				Write-Error "$_.Exception.Message"
				}
                        }
            TestScript = {
				if ((Get-Content "$using:SiteLoc\Web.config") -match '<system.web.>'){return $False} else {return $True}
                         }
            GetScript = {return "File exist"}
            DependsOn = "[Archive]TargetZip"
            }
			
			
        Script SiteConfig{
            SetScript = {
			    try{
				    Stop-Website "Default Web Site"
                    if (!(Test-Path IIS:\AppPools\TargetTest) )
                    {
				    New-WebAppPool -Name TargetTest -Force
                    }
				    New-Website -Name TargetTest -ApplicationPool TargetTest -PhysicalPath $using:SiteLoc -Port 80 -Force
				    sleep 15
				    $web = New-Object Net.WebClient
				    $string = $web.DownloadString("http://localhost")
				    if ($string -match "<title>Home Page - My ASP.NET Application</title>")
				    {

				    $attachments = @(@{
					    "pretext" = "Node is in desired state. Site is available"
					    })
				    $payload = 
					    @{
					    "attachments" = $attachments
					    }

					    $info = (Invoke-WebRequest -Body (ConvertTo-Json -Compress -InputObject $payload) -Method Post -UseBasicParsing -Uri $using:SlackCh | Format-List -Property StatusCode, StatusDescription | Out-String)
                        Out-File -FilePath $using:LogFile -Append -InputObject "$(Get-Date -Format g) [Script]FindError $info" 
                   
				    }
				    }
			    catch{
				    $exception = $_.Exception.Message 
				    Out-File -FilePath $using:LogFile -Append -InputObject "$(Get-Date -Format g) [Script]SiteConfig  $exception"
				    Write-Error "$_.Exception.Message"
				    }
					    }
					
            TestScript = 
            {
            try{
			    $web = New-Object Net.WebClient
			    $string = $web.DownloadString("http://localhost")
			    if ($string -match "<title>Home Page - My ASP.NET Application</title>") 
                    {
				    return $true
                    }
			    else {
                    return $false
                        }}
                catch{return $false}}

		    GetScript = {return "File exist"}
            DependsOn = "[Script]FindError"            
                }

        }}
TargetTest 
Set-DscLocalConfigurationManager -Path .\TargetTest
Start-DscConfiguration -Path .\TargetTest -Verbose -Wait
