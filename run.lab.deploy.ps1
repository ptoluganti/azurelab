Import-Module Build.IPUtils

function Get-NextAvailableSubnet
{
	<#

	.SYNOPSIS

	.DESCRIPTION

	.PARAMETER 

	.PARAMETER

	.EXAMPLE

	.NOTES

	#>
	[cmdletbinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory=$true)]
		[Microsoft.Azure.Commands.Network.Models.PSTopLevelResource]$vNet,
		[Parameter(Mandatory=$true)]
		[string]$fromCIDR,
		[Parameter(Mandatory=$true)]
		[int]$numberOfIpsRequired
	)
	process
	{
		if($PSCmdlet.ShouldProcess($vNet.Name))
		{
			# Validate input starting range
	<#		$startingCIDR = "10.0.0.0/29";
			if (![string]::IsNullOrEmpty($fromCIDR))
			{
				
			}
#>

            $startingCIDR = $fromCIDR;
	
			if ($startingCIDR.Contains("/")) 
			{
				$temp = $startingCIDR.Split("/")
				$IP = $temp[0]
			}
			else 
			{
				throw 'Get-NextAvailableSubnet expects FromCIDR range specification ending with /x (no foreslash found).'
			}

			# Get existing subnets
			$subnetsInUse = $vNet.Subnets | ForEach-Object {$_.AddressPrefix} | Sort-Object { ConvertTo-DecimalIP $_.Split('/')[0] }
		
			$nextSubnet = $null;
			$isValidSubnet = $true
			$count = 1
			do
			{
				$nextSubnet = Get-NextSubnet -CIDR $startingCIDR -NumberOfIpsRequired $numberOfIpsRequired

				$startingCIDR = $nextSubnet
				$isValidSubnet = $true

				foreach($subnet in $subnetsInUse)
				{
					$result = SubnetsOverlap -aSubnet $nextSubnet -bSubnet $subnet
					if($result)
					{
						$isValidSubnet = $false
						break;       
					}
				}
			
				$count++      
			}
			while ($isValidSubnet -ne $true)
		
			Write-Output $nextSubnet
		}
	}    
}