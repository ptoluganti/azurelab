function ConvertTo-BinaryIP {
    <#
    .Synopsis
      Converts a Decimal IP address into a binary format.
    .Description
      ConvertTo-BinaryIP uses System.Convert to switch between decimal and binary format. The output from this function is dotted binary.
    .Parameter IPAddress
      An IP Address to convert.
  #>

    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Net.IPAddress]$IPAddress
    )

    process {  
        return [String]::Join('.', $( $IPAddress.GetAddressBytes() |
            ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') } ))
}
}

function ConvertTo-DecimalIP {
    <#
    .Synopsis
      Converts a Decimal IP address into a 32-bit unsigned integer.
    .Description
      ConvertTo-DecimalIP takes a decimal IP, uses a shift-like operation on each octet and returns a single UInt32 value.
    .Parameter IPAddress
      An IP Address to convert.
  #>
  
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Net.IPAddress]$IPAddress
    )

    process {
        $i = 3; $DecimalIP = 0;
        $IPAddress.GetAddressBytes() | ForEach-Object { $DecimalIP += $_ * [Math]::Pow(256, $i); $i-- }

        return [UInt32]$DecimalIP
    }
}

function ConvertTo-DottedDecimalIP {
    <#
    .Synopsis
      Returns a dotted decimal IP address from either an unsigned 32-bit integer or a dotted binary string.
    .Description
      ConvertTo-DottedDecimalIP uses a regular expression match on the input string to convert to an IP address.
    .Parameter IPAddress
      A string representation of an IP address from either UInt32 or dotted binary.
  #>

    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]$IPAddress
    )
  
    process {
        Switch -RegEx ($IPAddress) {
            "([01]{8}.){3}[01]{8}" {
                return [String]::Join('.', $( $IPAddress.Split('.') | ForEach-Object { [Convert]::ToUInt32($_, 2) } ))
        }
        "\d" {
            $IPAddress = [UInt32]$IPAddress
            $DottedIP = $( For ($i = 3; $i -gt -1; $i--) {
                $Remainder = $IPAddress % [Math]::Pow(256, $i)
                ($IPAddress - $Remainder) / [Math]::Pow(256, $i)
                $IPAddress = $Remainder
            } )
       
        return [String]::Join('.', $DottedIP)
    }
    default {
        Write-Error "Cannot convert this format"
    }
}
}
}

function ConvertTo-MaskLength {
    <#
    .Synopsis
      Returns the length of a subnet mask.
    .Description
      ConvertTo-MaskLength accepts any IPv4 address as input, however the output value 
      only makes sense when using a subnet mask.
    .Parameter SubnetMask
      A subnet mask to convert into length
  #>

    [CmdLetBinding()]
    param
    (
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        [Alias("Mask")]
        [Net.IPAddress]$SubnetMask
    )

    process {
        $Bits = "$( $SubnetMask.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2) } )" -replace '[\s0]'

        return $Bits.Length
    }
}

function ConvertTo-Mask {
    <#
    .Synopsis
      Returns a dotted decimal subnet mask from a mask length.
    .Description
      ConvertTo-Mask returns a subnet mask in dotted decimal format from an integer value ranging 
      between 0 and 32. ConvertTo-Mask first creates a binary string from the length, converts 
      that to an unsigned 32-bit integer then calls ConvertTo-DottedDecimalIP to complete the operation.
    .Parameter MaskLength
      The number of bits which must be masked.
  #>
  
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Alias("Length")]
        [ValidateRange(0, 32)]
        $MaskLength
    )
  
    Process {
        return ConvertTo-DottedDecimalIP ([Convert]::ToUInt32($(("1" * $MaskLength).PadRight(32, "0")), 2))
}
}

function Get-NextSubnet ( [String]$CIDR, [int]$NumberOfIpsRequired ) {
    if ($CIDR.Contains("/")) {
        $Temp = $CIDR.Split("/")
        $IP = $Temp[0]
        $Mask = $Temp[1]
    }
    else {
        throw 'Get-NextSubnet expects CIDR range specification ending with /x (no foreslash found).'
    }
    $mk = ConvertTo-Mask -MaskLength $Mask
    $DecimalIP = ConvertTo-DecimalIP $IP
    $DecimalMask = ConvertTo-DecimalIP -IPAddress $mk 
    $nex = $DecimalIP -bor `
    ((-bnot $DecimalMask) -band [UInt32]::MaxValue)
    $Next = ConvertTo-DottedDecimalIP ($nex + 1)
  
    $thisRangeCIDR = GetCIDRSuffix -RangeSize $NumberOfIpsRequired;
    return $Next + "/" + $thisRangeCIDR;
}

function Get-DnsIpAddress ( [String]$IP) {
    if ($IP.Contains("/")) {
        $Temp = $IP.Split("/")
        $IP = $Temp[0]
        $Mask = $Temp[1]
    }
    else {
        $Mask = "";
    }
    $mk = ConvertTo-Mask -MaskLength $Mask
    $DecimalIP = ConvertTo-DecimalIP $IP
    $DecimalMask = ConvertTo-DecimalIP -IPAddress $mk
  
    $Network = $DecimalIP -band $DecimalMask
   
    $dns = ConvertTo-DottedDecimalIP ($Network + 4)
    return $dns
}

function Get-NetworkAddress {
    <#
    .Synopsis
      Takes an IP address and subnet mask then calculates the network address for the range.
    .Description
      Get-NetworkAddress returns the network address for a subnet by performing a bitwise AND 
      operation against the decimal forms of the IP address and subnet mask. Get-NetworkAddress 
      expects both the IP address and subnet mask in dotted decimal format.
    .Parameter IPAddress
      Any IP address within the network range.
    .Parameter SubnetMask
      The subnet mask for the network.
  #>
  
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Net.IPAddress]$IPAddress,
    
        [Parameter(Mandatory = $true, Position = 1)]
        [Alias("Mask")]
        [Net.IPAddress]$SubnetMask
    )

    process {
        return ConvertTo-DottedDecimalIP ((ConvertTo-DecimalIP $IPAddress) -band (ConvertTo-DecimalIP $SubnetMask))
    }
}

function Get-BroadcastAddress {
    <#
    .Synopsis
      Takes an IP address and subnet mask then calculates the broadcast address for the range.
    .Description
      Get-BroadcastAddress returns the broadcast address for a subnet by performing a bitwise AND 
      operation against the decimal forms of the IP address and inverted subnet mask. 
      Get-BroadcastAddress expects both the IP address and subnet mask in dotted decimal format.
    .Parameter IPAddress
      Any IP address within the network range.
    .Parameter SubnetMask
      The subnet mask for the network.
  #>
  
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [Net.IPAddress]$IPAddress, 
    
        [Parameter(Mandatory = $true, Position = 1)]
        [Alias("Mask")]
        [Net.IPAddress]$SubnetMask
    )

    process {
        return ConvertTo-DottedDecimalIP $((ConvertTo-DecimalIP $IPAddress) -bor `
      ((-bnot (ConvertTo-DecimalIP $SubnetMask)) -band [UInt32]::MaxValue))
}
}

function GetCIDRSuffix {
    <#
    .Synopsis
      Convert the specified integer number of IP addresses into the smallest CIDR suffix
    .Description
    .Parameter RangeSize
      The number of IP addresses to cater for
  #>
  
    [CmdLetBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateRange(0, 255)]
        $RangeSize
    )
  
    process {
        #  In ARM you get an error if specifying more than /29 (fewer than 8 addresses)
        <#if ($RangeSize -le 1) { return "32"; }
    elseif ($RangeSize -le 2) { return "31"; }
    elseif ($RangeSize -le 4) { return "30"; }
    else#>
        if ($RangeSize -le 8) {
            return "29"; 
        }
        elseif ($RangeSize -le 16) {
            return "28"; 
        }
        elseif ($RangeSize -le 32) {
            return "27"; 
        }
        elseif ($RangeSize -le 64) {
            return "26"; 
        }
        elseif ($RangeSize -le 128) {
            return "25"; 
        }
        elseif ($RangeSize -le 256) {
            return "24"; 
        }
    }
}

function GetIpsInSubnet {
    <#
    .Synopsis
      Convert the specified CIDR subnet suffix into the number of IP addresses in the range.
    .Description
    .Parameter RangeSize
      Accommodates CIDR subnets 22 to 32
  #>
  
    [CmdLetBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateRange(21, 32)]
        $SubnetSuffix
    )
  
    process {
        if ($SubnetSuffix -eq 32) {
            return "1"; 
        }
        elseif ($SubnetSuffix -eq 31) {
            return "2"; 
        }
        elseif ($SubnetSuffix -eq 30) {
            return "4"; 
        }
        elseif ($SubnetSuffix -eq 29) {
            return "8"; 
        }
        elseif ($SubnetSuffix -eq 28) {
            return "16"; 
        }
        elseif ($SubnetSuffix -eq 27) {
            return "32"; 
        }
        elseif ($SubnetSuffix -eq 26) {
            return "64"; 
        }
        elseif ($SubnetSuffix -eq 25) {
            return "128"; 
        }
        elseif ($SubnetSuffix -eq 24) {
            return "256"; 
        }
        elseif ($SubnetSuffix -eq 23) {
            return "512"; 
        }
        elseif ($SubnetSuffix -eq 22) {
            return "1024"; 
        }
        elseif ($SubnetSuffix -eq 21) {
            return "2048"; 
        }
    }
}

function SubnetsOverlap {
    [CmdLetBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$aSubnet,        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$bSubnet
    )

    if ($aSubnet.Contains("/")) {
        $Temp = $aSubnet.Split("/")
        $IP = $Temp[0]
        $Mask = $Temp[1]
    }
    else {
        throw 'SubnetsOverlap expects CIDR range specification ending with /x (no foreslash found).'
    }
    # start of range a
    [UInt32]$startArange = Get-DnsIpAddress($aSubnet) | ConvertTo-DecimalIP;
    [int]$ipsInRange = GetIpsInSubnet -SubnetSuffix $Mask
    [UInt32]$endArange = ($startArange + $ipsInRange - 1);

    
    if ($bSubnet.Contains("/")) {
        $Temp = $bSubnet.Split("/")
        $IP = $Temp[0]
        $Mask = $Temp[1]
    }
    else {
        throw 'SubnetsOverlap expects CIDR range specification ending with /x (no foreslash found).'
    }
    # start of range a
    [UInt32]$startBrange = Get-DnsIpAddress($bSubnet) | ConvertTo-DecimalIP;
    [int]$ipsInRange = GetIpsInSubnet -SubnetSuffix $Mask
    [UInt32]$endBrange = ($startBrange + $ipsInRange - 1);

    $overlap = $false;
    if ($startBrange -le $endArange) {
        if ($endBrange -ge $startArange) {
            $overlap = $true;
        }
    }
    return $overlap;
}