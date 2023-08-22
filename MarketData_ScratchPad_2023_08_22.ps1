$dataPath="/Users/colingordon/Downloads/HistoricalData_1690269838678.csv" 

$rawData = import-csv -Path $dataPath


function mean
{
    <#
     This is a simple function that finds the 
     mean of data from a given array
    #>
    param(
        [Array]$data
    )

    $retVal = 0

    foreach($point in $data)
    {
        $retVal+=$point
    }

    $retVal = $retVal/($data.Count)

    return $retVal
}


function relativeChangeData
{
    <#
    This function approximates the relative change 
    per a given data set. in this case I was using data
    from https://www.marketwatch.com/investing/index/spx/download-data
    where I was comparing open values of the day. 
    
    Formulation is that continuous Interest rate = dLog(data.Open)/dtime
    
    I excluded data that gave infinite solutions. also assumed the market
    opened the same time each day to estimate dtime
    dLog(data.Open) => $logDiff = [Math]::Log($data[$i].Open) - [Math]::Log($data[$i+1].Open)
    dtime => $timeDiff= (New-TimeSpan -End $data[$i].Date -Start $data[$i+1].Date).TotalDays

    
    #>
    param(
        [Array]$data        
    )

    $lastPoint=$data.Count - 1
    $table = @()
    for($i=0;$i -lt $lastPoint;$i++)
    {
        $logDiff = [Math]::Log($data[$i].Open) - [Math]::Log($data[$i+1].Open)
        if($logDiff -ne [double]::PositiveInfinity -and $logDiff -ne [double]::NegativeInfinity)
        {
            $timeDiff= (New-TimeSpan -End $data[$i].Date -Start $data[$i+1].Date).TotalDays
            $date = [datetime]::parseexact($data[$i].Date,'MM/dd/yyyy',$null).AddDays(-0.5*$timeDiff)
            $value = $logDiff*365/$timeDiff
            $record = [PSCustomObject]@{
                date = $date
                value = $value
            }

            $table+=$record
        }
    }

    return $table


}

function std 
{
    <#
    Simple function used to calculate the 
    standard deviation of data. 
    #>
    param(
        [Array]$data,
        [double]$mean
    )
    if(-not($mean))
    {
        $mean = mean -data $data
    }

    $sqr = [double]0

    foreach($point in $data)
    {
        $sqr += ([double]$point)*([double]$point)
    }

    $sqr = $sqr/($data.Count)

    return [math]::Sqrt($sqr - $mean*$mean)

}

function MaxMin
{
    <#
    Simple function to extract the min and maximum 
    of a data set. 
    #>
    param(
        [array]$data
    )

    $min = $data[0]
    $max = $data[0]

    foreach($point in $data)
    {
        if($point -lt $min)
        {
            $min = $point
        }
        elseif ($point -gt $max) {
            $max = $point
        }
    }

    $retVal = [PSCustomObject]@{
        Min = $min
        Max = $max
    }

    return $retVal
}


<#
This section below is testing functions above by calculating various values of 
means/stds/max min
#>
$openMean = mean -data $rawData.Open
$openStd = std -data $rawData.Open -mean $openMean

$closeMean = mean -data $rawData."Close/Last"
$closeStd = std -data $rawData."Close/Last" -mean $closeMean

$diff = ($openMean-$closeMean)/([Math]::Sqrt($openStd*$openStd+$closeStd*$closeStd))

$maxMin = MaxMin -data $rawData.Open


function histoGram
{
    <#
    .SYNOPSIS
    This function creates an ordered hash 
    that represents a histogram. the key for 
    this hash is the center of the bin and the value
    is a pscustomobject with histogram attributes
    
    .DESCRIPTION
    this function generates a histogram for a given 
    data set array [array]$data. the return of this 
    function results in an ordered hash with a key
    defined at the center of the bin and the value 
    is a pscustomobject with histogram attributes. 

    the value for each key is of the form
    $record = [PSCustomObject]@{
            Min = binMin
            Max = binMax
            Frequency = count
            Density = count/(partionSize*TotalFrequency)
        }
    Algo:
        1.) generates missing values
        2.) defines the bin size and number of partitions
        3.) starts forloop for each bin
            3a.)foreach loop counts every point in data set that
            is in bin (could be optimized)
            3b.) adds element to hash table with density incomplete
        4.) goes through and divdes the density by the totalfrequency
        5.) returns the hash created
    
    
    
    DEPENDENCIES
    -------------------------
    the minimum requirement 
    to use this frunction is to have the variable [array]data
    defined and the [double]frac defined.

    if mean,std,min,max are not defined, the function will use
    the various functions defined above to calculate those values. 



    
    .PARAMETER [Array]data
    this is the array of data that you implement this function on 
    
    .PARAMETER [double]mean
    this is the mean of that data set. if the parameter is not
    specified it will calculate the mean with the mean function above

    .PARAMETER [double]std
    this is the standard deviation of the data set. if the parameter
    is not specified, it will caclulate the std with std function above.

    .PARAMETER [double]frac
    this is the fraction that defines how many standard deviations
    wide is your bin/parition size. as an example you can set frac=0.05 
    which would mean your bins are a 20th of a standard deviation in 
    size. 

    .PARAMETER [double]min
    this is the minimum of your data set. if this is not calculated 
    this function will use the MaxMin function to calculate the min

    .PARAMETER [double]max
    this is the maximum of your data set. if this is not calculated 
    this function will use the MaxMin function to calculate the max

    
    .EXAMPLE
    
    .NOTES
    #>
    param(
        [Array]$data,
        [double]$mean,
        [double]$std,
        [double]$frac,
        [double]$min,
        [double]$max
    )

    if(-not($mean))
    {
        $mean = mean -data $data
    }
    if(-not($std))
    {
        $std = std -data $data -mean $mean
    }
    if(-not($min) -or -not($max))
    {
        $maxMinObj = MaxMin -data $data
        $min = $maxMinObj.Min
        $max = $maxMinObj.Max
    }

    # partition size
    $partSize = $frac*$std

    # number of partitions
    $numPart = [Math]::Ceiling(($max-$min)/$partSize)
    $binMin = $min 
    $binMax = $min + $partSize
    $table = [ordered]@{}
    $totalFreq = 0
    for($i=0;$i -lt $numPart;$i++)
    {
        
        $count = 0 
        foreach($point in $data)
        {
            #counting the number of points in partition
            if($point -ge $binMin -and $point -lt $binMax)
            {
                $count++
                $totalFreq++
            }
        }
        
        $record = [PSCustomObject]@{
            Min = $binMin
            Max = $binMax
            Frequency = $count
            Density = $count/($partSize)
        }

        $key = ($binMin+$binMax)/2

        $table.Add($key,$record)

        $binMin+=$partSize
        $binMax+=$partSize

    }
    foreach($key in $table.Keys)
    {
        $table[$key].Density = $table[$key].Density/$totalFreq
    }

    return $table

}

<#
this below is an intial histogram created from the raw data testing the functions capability
#>
$histoGram = histoGram -data $rawData.Open -mean $openMean -std $openStd -frac 0.05 -min $maxMin.Min -max $maxMin.Max

$outFilePath = "/Users/colingordon/Downloads/SP500HistoGram.csv"
"Bin,Frequency,Min,Max" | out-file -Path $outFilePath
foreach($key in $histoGram.Keys)
{
    $tempStr=($key.ToString()) + "," + ($histoGram[$key].Frequency.ToString()) + "," + ($histoGram[$key].Min.ToString()) + "," + ($histoGram[$key].Max.ToString())
    $tempStr | out-file -Path $outFilePath -Append
}


<#
I used the functions above to take the raw data from the pricing of the 
S&P 500 to turn it to a sampling measurement of the continual rate of interest.

the code below creates the relativeChangeData that produced the continual rate of 
interest according to day in between any two data points. 

from there I create a histogram of the continual rates of interest and output it into 
a file. 
#>
$changes = relativeChangeData -data $rawData
$changeOGram = histoGram -data $changes.value -frac 0.01


$outFilePath = "/Users/colingordon/Downloads/SP500ChangeOGram2.csv"
"Bin,Density,Frequency,Min,Max" | out-file -Path $outFilePath
foreach($key in $changeOGram.Keys)
{
    $tempStr=($key.ToString())+ "," + ($changeOGram[$key].Density.ToString()) + "," + ($changeOGram[$key].Frequency.ToString()) + "," + ($changeOGram[$key].Min.ToString()) + "," + ($changeOGram[$key].Max.ToString())
    $tempStr | out-file -Path $outFilePath -Append
}



# This function will define the interval of 
# continuous interest rates to a probability space 
# inside the interval of [0,1]

function deltaFunctionCalculator 
{
    <#
    .SYNOPSIS
    This defines end points of the intervals
    of standardized interest rates that have near 
    constant probability distribution among the interest rates
    among the interval
    
    .DESCRIPTION
    the step size is an estimate of how much percentage change
    there varies among the interval.
    Delta(StepNumber+1)-Delta(StepNumber)=<
    StepSize/dLog(rho)/ddelta

    for a lorentzian distribution
    Delta(StepNumber+1)<=Delta(StepNumber)(1+h/2)+h/(2Delta(StepNumber))
    which we can use Delta(StepNumber)(1+h/2)
    to define the step size due to the extra h/(2Delta(StepNumber))>=0
    hence we define an exponential relationship
    where 
    Delta(StepNumber)=Delta(0)(1+h/2)^StepNumber


    
    .PARAMETER StepSize
    This is the allowed percentage change among 
    the interest rates
    
    .PARAMETER StepNumber
    The iteration of step that is being used
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [double]$StepSize,
        [int]$StepNumber
    )

    # This is used to define our 
    $Delta0 = [Math]::SQRT($StepSize)
    # Step number of 0 will return the original delta length
    if($StepNumber -eq 0)
    {
        return $Delta0
    }
    $ratio =1+($StepSize/2)
    $ratPow = [Math]::Pow($ratio,$StepNumber)
    $value = $Delta0*$ratPow
    return $value
    
}


function MaxStepNumber
{
    <#
    .SYNOPSIS
    deltaFunctionCalculator function
    requires a max step size that 
    will be iterated to encompass 
    the probability space
    
    .DESCRIPTION
    Technically the size of all possible interest
    rates is the whole real number line. 
    a computer is incapable of dealing with infinite
    intervals hence we need to cap the amount of possible
    interest rates.
    
    the exact equation is 
    Log(tan(piPmax/2)/h^.5)/Log(1+h/2)
    however this function approximates this value by assuming
    Pmax is really close to 1. (approximation will choose bigger k)
    0.5Log(4/(pi^2StepSize(1-PMax)^2))/Log(1+h/2)
    

    .PARAMETER StepSize
    This is the step size use to calculate the 
    Delta regions in deltaFunctionCalculator. 
    the step size is an estimate of how much percentage change
    there varies among the interval.
    Delta(StepNumber+1)-Delta(StepNumber)=<
    StepSize/dLog(rho)/ddelta

    .PARAMETER PMax
    The stochastic probability space
    we are creating will only have a finite range
    of interest rates to choose from. 
    due to this we will choose the cap on our interest
    rates by how much of the probabilty space we encompass.
    In this case we encompass PMax which should be set to always
    be less than 1 and be greater than 0.99
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [double]$StepSize,
        [double]$PMax
    )

    $base = 1+$StepSize/2
    $numeratorLog = 4/(([Math]::PI)*([Math]::PI)*$StepSize*(1-$PMax)*(1-$PMax))
    $maxKapprox = [Math]::Log($numeratorLog)/[Math]::Log($base)
    $maxK = [Math]::Ceiling($maxKapprox)
    return $maxK

}

function ProbabilityIntervals
{   
    <#
    .SYNOPSIS
    This function creates a list of 
    intervals that can be used by random number 
    generator to determine the interest rate
    
    .DESCRIPTION
    Since random number generators choose uniformily
    random number in the interval [0,1]
    it can't be directly used for an interest rate.
    to do so we break [0,1] into intervals where
    if the random number lands in an interval
    say [Pk,Pk+1] this finds the an associate
    range of deltas [a,b] where
    Prob([a,b])=length([Pk,Pk+1])
    and [a,b] has a probability 
    variance of $StepSize, meaning the distribution 
    of interest rates among [a,b] can be chosen
    by a pseudo number generator by choosing a 
    number in [0,1] and mapping it
    to the interest rate = a+number(b-a) 

    

    .PARAMETER StepSize
    This is the step size use to calculate the 
    Delta regions in deltaFunctionCalculator. 
    the step size is an estimate of how much percentage change
    there varies among the interval.
    Delta(StepNumber+1)-Delta(StepNumber)=<
    StepSize/dLog(rho)/ddelta

    .PARAMETER PMax
    The stochastic probability space
    we are creating will only have a finite range
    of interest rates to choose from. 
    due to this we will choose the cap on our interest
    rates by how much of the probabilty space we encompass.
    In this case we encompass PMax which should be set to always
    be less than 1 and be greater than 0.99
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [double]$StepSize,
        [double]$PMax
    )

    # This is roughly half the intervals that make up our partitions
    $gMax= MaxStepNumber -StepSize $StepSize -PMax $PMax
    # this is the first step size calculated
    $Delta0 = deltaFunctionCalculator -StepSize $StepSize -StepNumber 0
    #The first record is the center of the distribution. 
    # due to the derivative being zero, the region was calculated uniquely
    $P = 2*[Math]::Atan($Delta0)/[Math]::PI
    $record = [PSCustomObject]@{
        InterestMin = -$Delta0
        InterestMax = $Delta0
        ProbMin = 0
        ProbMax = $P
    }
    $table =@()
    $table+=$record
    $kMax = 2*$gMax+1
    for($k=1; $k -lt $kMax; $k++)
    {
        if($k % 2 -eq 1)
        {
            $g = ($k-1)/2
            $Deltag = deltaFunctionCalculator -StepSize $StepSize -StepNumber $g
            $Deltag1 = deltaFunctionCalculator -StepSize $StepSize -StepNumber ($g+1)
            $record = [PSCustomObject]@{
                InterestMin = $Deltag
                InterestMax = $Deltag1
                ProbMin = $P
                ProbMax = $P
            }
            $deltaP = ([Math]::Atan($Deltag1)-[Math]::Atan($Deltag))/[Math]::PI
            $record.ProbMax += $deltaP
            $table+=$record
            $P = $record.ProbMax
        }
        else
        {
            $record = [PSCustomObject]@{
                InterestMin = -1*$Deltag1
                InterestMax = -1*$Deltag
                ProbMin = $P
                ProbMax = $P+$deltaP
            }
            $table+=$record
            $P = $record.ProbMax
        }
    }
    # the last interval contains all possible probabilities not partitioned by
    # this function. the nature of $record.ProbMax=1 can signify if that the 
    # the random variable bin needs to use the exponential mapping to find the interest rate
    $Deltag = -1*(deltaFunctionCalculator -StepSize $StepSize -StepNumber $gmax)
    $Deltag1 = -1*$Deltag1
    $record = [PSCustomObject]@{
        InterestMin = $Deltag
        InterestMax = $Deltag1
        ProbMin = $P
        ProbMax = 1
    }

    $table+=$record

    return $table
   


}


function RandomDeltaGenerator
{
    <#
    .SYNOPSIS
    This generates a single random 
    Delta which can be used to calculate 
    the force of interest. 
    Delta = (Interest-InterestLorentzMean)/LorentzVarianceInterest
    
    .DESCRIPTION
    This calculates a random Delta defined to be related
    to the force interest in the equation
    Delta = (Interest-InterestLorentzMean)/LorentzVarianceInterest



    .PARAMETER StepSize
    This is the step size use to calculate the 
    Delta regions in deltaFunctionCalculator. 
    the step size is an estimate of how much percentage change
    there varies among the interval.
    Delta(StepNumber+1)-Delta(StepNumber)=<
    StepSize/dLog(rho)/ddelta
    
    .PARAMETER PMax
    The stochastic probability space
    we are creating will only have a finite range
    of interest rates to choose from. 
    due to this we will choose the cap on our interest
    rates by how much of the probabilty space we encompass.
    In this case we encompass PMax which should be set to always
    be less than 1 and be greater than 0.99
    
    .PARAMETER NumberOfPoints
    this is the number of points generated per a given
    instance (it is more efficient to use the same intervallist over
    and over thus do a number of points at a time)

    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [double]$StepSize,
        [double]$PMax,
        [int]$NumberOfPoints
    )

    $intervalList = ProbabilityIntervals -StepSize $StepSize -PMax $PMax

    $RandomTable=New-Object double[] $NumberOfPoints
    for($i=0;$i -lt $NumberOfPoints;$i++)
    {
        $rand1=Get-Random -Minimum 0.0 -Maximum 1.0
        if($rand1 -lt $intervalList[0].ProbMax)
        {
            $interval = $intervalList[0]
            #write-host 0
            
        }
        else{
            for($j=1;$j -lt $intervalList.Count; $j++)
            {
                if($rand1 -lt $intervalList[$j].ProbMax -and $rand1 -ge $intervalList[$j].ProbMin)
                {
                    $interval = $intervalList[$j]
                    #write-host $j -Foreground Green
                    break
                }
            }
        }

        if($interval.ProbMax -eq 1)
        {
            $rand2 = Get-Random -Minimum 0.0 -Maximum 1,0
            $R = [Math]::Floor(-1*[Math]::Log($rand2)/[Math]::Log(1+$StepSize/2))
            $bottom=$kMax+$R
            $top = $bottom+1
            $Deltabottom = deltaFunctionCalculator -StepSize $StepSize -StepNumber $bottom
            $Deltagtop = deltaFunctionCalculator -StepSize $StepSize -StepNumber $top

            $rand3 = Get-Random -Minimum $Deltabottom -Maximum $Deltagtop

            $negOrPos = Get-Random -Minimum 0.0 -Maximum 1.0
            while($negOrPos -eq 0.5)
            {
                $negOrPos = Get-Random -Minimum 0.0 -Maximum 1.0
                
            }
            if($negOrPos -lt 0.5)
            {
                $finalRand = -1*$rand3
            }
            else {
                $finalRand = $rand3
            }
            
        }
        else {
            $finalRand = Get-Random -Minimum $interval.InterestMin -Maximum $interval.InterestMax
            
        }
        $RandomTable[$i]=$finalRand
        if($i % 100 -eq 0)
        {
            write-host $i done
        }
    }
    return $RandomTable

}



## Testing Random Delta Generator by putting it in a histogram

$deltaTable= RandomDeltaGenerator -StepSize 0.01 -PMax 0.999 -NumberOfPoints 20000
$deltaHistoGram = histoGram -data $deltaTable -frac 0.001


function integratedFunction
{
    <#
    .Synopsis
    This is evaluates the gamma = 1, mu = 0 Lorentzian
    #>
    param(
        [double]$x
    )

    $y = 1.0/([math]::PI*($x*$x+1.0))
    return $y
}


$outFilePath = "/Users/colingordon/DeltaHistoMeter2.csv"

function exportHistoGram
{
    <#
    .Synopsis
    This exports the histogram into a csv format
    #>

    param(
        [Object]$histoGram,
        [string]$outFilePath
    )
    "Bin,Density,Fit,Frequency,Min,Max" | out-file -Path $outFilePath

    foreach($key in $histoGram.Keys)
    {
        $value = [string](integratedFunction -x $key)
        $tempStr=($key.ToString()) + ","+ ($histoGram[$key].Density.ToString())+ "," +$value+","+ ($histoGram[$key].Frequency.ToString()) + "," + ($histoGram[$key].Min.ToString()) + "," + ($histoGram[$key].Max.ToString())
        $tempStr | out-file -Path $outFilePath -Append
    }
}

function chiSquared
{
    <#
    .Synopsis
    This function calculates chi^2 from a histogram and
    a function called integratedFunction. it also calculates
    the effective innerproducts
    #>
    param(
        [object]$histoGram
    )
    $DensDens=0
    $DensFit=0
    $FitFit=0
    $count = 0
    foreach($key in $histoGram.Keys)
    {
        $fit=integratedFunction -x $key
        $DensDens += ($histoGram[$count].Density)*($histoGram[$count].Density)
        $DensFit += ($histoGram[$count].Density)*$fit
        $FitFit += $fit*$fit
        $count++

    }

    $varRecord = [PSCustomObject]@{
        DensSquared = $DensDens
        DensFit = $DensFit
        FitSquared= $FitFit
        ChiSquared = $DensDens+$FitFit-2*$DensFit
        }
    
    return $varRecord

}


exportHistoGram -histoGram $deltaHistoGram -outFilePath $outFilePath

#Simpiler export for testing purposes
foreach($key in $deltaHistoGram.Keys)
{
    if($deltaHistoGram[$key].Frequency -gt 1)
    {
        write-host $key has frequency $deltaHistoGram[$key].Frequency
    }
}



### Large Data Generator Csv
## We will generate a 1,000,000 data points to use as our

$deltaTable= RandomDeltaGenerator -StepSize 0.01 -PMax 0.999 -NumberOfPoints 1000000
$exportPath = "/Users/colingordon/RandomDataExport.csv"

foreach($line in $deltaTable)
{
    $line | out-file -Append -FilePath $exportPath
    <#
    # create a new file using the provider cmdlets
    $newFile = New-Item -Name output.csv -ItemType File

    try {
    # open a writable FileStream
    $fileStream = $newFile.OpenWrite()

    # create stream writer
    $streamWriter = [System.IO.StreamWriter]::new($fileStream)

    # write to stream
    $streamWriter.WriteLine("Some, text")
    }
    finally {
    # clean up
    $streamWriter.Dispose()
    $fileStream.Dispose()
    }

    #>
}

function AccumulationFunctionGenerator
{
    <#
    .SYNOPSIS
   This generates a single accumulation function by randomily choosing
   interest rates from a generated set of interest rates. 
    
    .DESCRIPTION
    This calculates a random Delta defined to be related
    to the force interest in the equation
    Delta = (Interest-InterestLorentzMean)/LorentzVarianceInterest



    .PARAMETER DeltaTable
    this is an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    

    .PARAMETER FilePath
    this is a file path that generates
    an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    
    .PARAMETER LorentzianMean
    This is the best fit lorentzian mean for the portfolio you would like
    to model
    in functional form this is x0 for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))
    
    .PARAMETER LorentzianVariance
    This is the best fit lorentzian varriance 
    in functional form this is y for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))

    .PARAMETER TimeStep
    This is the time step for the accumulation function.
    usually set to be on the order of a day

    .PARAMETER TimeLength
    This is the length of time that the graph is generated
    for set in years

    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [Array]$DeltaTable,
        [string]$FilePath,
        [double]$LorentzianMean,
        [double]$LorentzianVariance,
        [double]$TimeStep,
        [double]$TimeLength
    )


    $acc = New-Object System.Collections.Generic.List[PSCustomObject]
    $record = [PSCustomObject]@{
        Step = 0
        Time = 0
        Delta = 0 
        Interest = 0
        SumTimeDelta = 0 
        SumTimeMeanInterest = 0
        TimeInterest = 0 

    }

    $TotalNumberSteps = [Math]::Ceiling($TimeLength/$TimeStep)
    $sumDelta = 0
    $SumTimeMeanInterest=0
    $effectiveDelta = 0
    $effectiveMeanInterest = 0 
    $sumTimeInterest = 0
    $accumulation = 1
    for($i=0;$i -lt $TotalNumberSteps;$i++)
    {
        $randInt = Get-Random -Minimum 0 -Maximum $DeltaTable.Count
        $randDelta = [double]$DeltaTable[$randInt]
        $interest = $randDelta*([double]$LorentzianVariance)+[double]$LorentzianMean
        $effectiveDelta +=$randDelta
        $effectiveMeanInterest += $LorentzianMean
        $sumTimeInterest += $interest*$TimeStep
        $sumTimeInterestLog10 = $sumTimeInterest/([Math]::Log(10))
        $accumulation = $accumulation*[Math]::Exp($interest*$TimeStep)
        $record = [PSCustomObject]@{
            Step = $i
            Time = $TimeStep*$i
            Delta = $randDelta 
            Interest = $interest
            SumDelta =  $effectiveDelta 
            AvgDelta = $effectiveDelta/($i+1)
            SumMeanInterest = $effectiveMeanInterest
            Accumulation = $accumulation
            Log10Acc = $sumTimeInterestLog10
            
        }
        $acc.Add($record)
    }

    return $acc


}


#$importPath = ""
#$DeltaTable = ""
$LorentzianMean = 0.216918871
$LorentzianVariance=1.268911575
$timeStep = 1.0/365
$testAccumulation = AccumulationFunctionGenerator -DeltaTable $deltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $timeStep -TimeLength 20

$testAccumulation | Export-Csv -Path "/Users/colingordon/testaccumulation.csv"





function GeneratingMultipleAccumulationFunctions
{
    <#
    .SYNOPSIS
    This generates a multiple accumulation function by randomily choosing
    interest rates from a generated set of interest rates. 
    
    .DESCRIPTION
    This calculates a random Delta defined to be related
    to the force interest in the equation
    Delta = (Interest-InterestLorentzMean)/LorentzVarianceInterest



    .PARAMETER DeltaTable
    this is an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    

    .PARAMETER FilePath
    this is a file path that generates
    an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    
    .PARAMETER LorentzianMean
    This is the best fit lorentzian mean for the portfolio you would like
    to model
    in functional form this is x0 for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))
    
    .PARAMETER LorentzianVariance
    This is the best fit lorentzian varriance 
    in functional form this is y for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))

    .PARAMETER TimeStep
    This is the time step for the accumulation function.
    usually set to be on the order of a day

    .PARAMETER TimeLength
    This is the length of time that the graph is generated
    for set in years

    .PARAMETER NumberOfFunctions
    This is the number of functions that 
    will be generated by this function

    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [Array]$DeltaTable,
        [string]$FilePath,
        [double]$LorentzianMean,
        [double]$LorentzianVariance,
        [double]$TimeStep,
        [double]$TimeLength,
        [int]$NumberOfFunctions
    )
    $TotalNumberSteps = [Math]::Ceiling($TimeLength/$TimeStep)
    $fileGenrator=New-Object string[] $TotalNumberSteps
    $Accumulation = AccumulationFunctionGenerator -DeltaTable $DeltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $TimeStep -TimeLength $TimeLength
    for($j=0;$j -lt $TotalNumberSteps;$j++)
    {
        $fileGenrator[$j] = $Accumulation[$j].Time.ToString() + "," + $Accumulation[$j].Accumulation.ToString()
    }
    for($i=1;$i -lt $NumberOfFunctions;$i++)
    {
        $Accumulation = AccumulationFunctionGenerator -DeltaTable $DeltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $TimeStep -TimeLength $TimeLength
        for($j=0;$j -lt $TotalNumberSteps;$j++)
        {
            $fileGenrator[$j] += "," + $Accumulation[$j].Accumulation.ToString()
        }

    }
    # create a new file using the provider cmdlets
    if(test-Path "/Users/colingordon/testaccumulation.csv")
    {
        remove-item -Path "/Users/colingordon/testaccumulation.csv"
    }
    $newFile = New-Item -Path "/Users/colingordon/testaccumulation.csv" -ItemType File

    try {
        # open a writable FileStream
        $fileStream = $newFile.OpenWrite()

        # create stream writer
        $streamWriter = [System.IO.StreamWriter]::new($fileStream)

        # write to stream
        foreach($line in $fileGenrator)
        {
            $streamWriter.WriteLine($line)
        }
    }
    finally {
        # clean up
        $streamWriter.Dispose()
        $fileStream.Dispose()
    }

}

function GeneratingMultipleLog10AccumulationFunctions
{
    <#
    .SYNOPSIS
    This generates a multiple accumulation function by randomily choosing
    interest rates from a generated set of interest rates. This differentiates
    from the previous function by calculating the Log10(a(t)) instead of calculating
    a(t).
    
    .DESCRIPTION
    This calculates a random Delta defined to be related
    to the force interest in the equation
    Delta = (Interest-InterestLorentzMean)/LorentzVarianceInterest



    .PARAMETER DeltaTable
    this is an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    

    .PARAMETER FilePath
    this is a file path that generates
    an array of generated values for a lorentzian 
    distribution with a lorentzian mean of 0 and lorentzian varainace
    of 1. 
    
    .PARAMETER LorentzianMean
    This is the best fit lorentzian mean for the portfolio you would like
    to model
    in functional form this is x0 for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))
    
    .PARAMETER LorentzianVariance
    This is the best fit lorentzian varriance 
    in functional form this is y for a probability density written as
    P(x) = y/(pi*(y^2+(x-x0)^2))

    .PARAMETER TimeStep
    This is the time step for the accumulation function.
    usually set to be on the order of a day

    .PARAMETER TimeLength
    This is the length of time that the graph is generated
    for set in years

    .PARAMETER NumberOfFunctions
    This is the number of functions that 
    will be generated by this function

    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    param(
        [Array]$DeltaTable,
        [string]$FilePath,
        [double]$LorentzianMean,
        [double]$LorentzianVariance,
        [double]$TimeStep,
        [double]$TimeLength,
        [int]$NumberOfFunctions
    )
    $TotalNumberSteps = [Math]::Ceiling($TimeLength/$TimeStep)
    $fileGenrator=New-Object string[] $TotalNumberSteps
    $Accumulation = AccumulationFunctionGenerator -DeltaTable $DeltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $TimeStep -TimeLength $TimeLength
    for($j=0;$j -lt $TotalNumberSteps;$j++)
    {
        $fileGenrator[$j] = $Accumulation[$j].Time.ToString() + "," + $Accumulation[$j].Log10Acc.ToString()
    }
    for($i=1;$i -lt $NumberOfFunctions;$i++)
    {
        $Accumulation = AccumulationFunctionGenerator -DeltaTable $DeltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $TimeStep -TimeLength $TimeLength
        for($j=0;$j -lt $TotalNumberSteps;$j++)
        {
            $fileGenrator[$j] += "," + $Accumulation[$j].Log10Acc.ToString()
        }

    }
    # create a new file using the provider cmdlets
    if(test-Path "/Users/colingordon/testaccumulation.csv")
    {
        remove-item -Path "/Users/colingordon/testaccumulation.csv"
    }
    $newFile = New-Item -Path "/Users/colingordon/testaccumulation.csv" -ItemType File

    try {
        # open a writable FileStream
        $fileStream = $newFile.OpenWrite()

        # create stream writer
        $streamWriter = [System.IO.StreamWriter]::new($fileStream)

        # write to stream
        foreach($line in $fileGenrator)
        {
            $streamWriter.WriteLine($line)
        }
    }
    finally {
        # clean up
        $streamWriter.Dispose()
        $fileStream.Dispose()
    }

}

$deltaTable = get-content -Path "/Users/colingordon/RandomDataExport.csv"
$LorentzianMean = 0.216918871
$LorentzianVariance=1.268911575
$timeStep = 1.0/365

GeneratingMultipleAccumulationFunctions -DeltaTable $deltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $timeStep -TimeLength 20 -NumberOfFunctions 20
GeneratingMultipleLog10AccumulationFunctions -DeltaTable $deltaTable -LorentzianMean $LorentzianMean -LorentzianVariance $LorentzianVariance -TimeStep $timeStep -TimeLength 20 -NumberOfFunctions 20





############# This function is a means of integrating dynamically with simpson's rule
###### The future usecase would be to normalize functions

function integratedFunction
{
    <#
    .Synopsis
    This is the function that
    you want to integrate. 
    #>
    
    param(
        [double]$x
    )

    $y = 1.0/([math]::PI*($x*$x+1.0))
    return $y
}

function derivativeFunction
{
    <#
    .Synopsis
    This is the derivative of the function that
    you want to integrate. 
    #>
    param(
        [double]$x
    )

    $y = -2.0*$x/([math]::PI*(1+$x*$x)*(1+$x*$x))

    return $y

}

function Integrate
{
    <#
    .Synopsis
    This integrates the function over the 
    interval [$min,$max]
    .Description
    This function uses simpson's rule
    to integrate a function. the step size
    is determined by $maxStep and $stepConst. 
    
    .Parameter maxStep
    this is the maximum step that
    is allowed in our integration

    .Parameter stepConst
    The stepConst is the allowed relative difference
    of the function for a step to take. 
    #>
    param(
        [double]$min,
        [double]$max,
        [double]$maxStep,
        [double]$stepConst
    )

    $integral = 0.0
    
    $a = $min
    while($a -lt $max)
    {
        $localDer = derivativeFunction -x $a
        $Left = integratedFunction -x $a
        $step = 0
        if($localDer -eq 0.0)
        {
            $step = $maxStep
        }
        else{

            $step = [math]::Abs($stepConst*$Left/$localDer)
            if($step -gt $maxStep)
            {
                $step = $maxStep
            }
        }
        $b = $a+$step

        if($b -gt $max)
        {
            $step = $max - $a
            $b = $max
        }

        $Mid = integratedFunction -x ($a+($step/2.0))
        
        $Right = integratedFunction -x $b

        $integral += ($Left+$Right+4.0*$Mid)*$step/6.0

        #write-host $integral
        #write-host $b

        $a = $b
    }

    return $integral

}


# Test integrate function
Integrate -min -1.0 -max 1.0 -maxStep 0.5 -stepConst .01

#Integrating from -inf to inf

$firstInt = Integrate -min -10.0 -max 10.0 -maxStep 100 -stepConst .01
$secondInt = Integrate -min -100.0 -max 100.0 -maxStep 100 -stepConst .01
$compInt = [math]::Abs(($firstInt-$secondInt)/$firstInt)
$bound = 100.0
while($compInt -gt 0.000001)
{
    $firstInt = $secondInt
    $bound = $bound*10.0
    $boundMin = -1.0*$bound
    $secondInt = Integrate -min $boundMin -max $bound -maxStep 1000 -stepConst .01
    $compInt = [math]::Abs(($firstInt-$secondInt)/$firstInt)

}

write-host $secondInt
write-host $compInt

for($number=1;$number -lt 10;$number++)
{
    $x = [math]::Pow(10.0, $number)
    $cumulative = Integrate -min $x -max $bound -maxStep 100 -stepConst .01
    $y = integratedFunction -x $x
    $yPrime = derivativeFunction -x $x

    $est = -1.0*$y*$y/$yPrime

    $difference = 100.0*($cumulative-$est)/$cumulative

    write-host at x=$x the cumulative is $cumulative, the estimate is $est with error of $difference 

}



