
#!/bin/bash
declare -A ProArr
declare -A NameArr
AlgoCounter=0
now="`date +%s`"
ShiftNumber=`redis-cli hget Pool_Stats This_Shift`
echo "Test"
startstring="Pool_Stats:"$ShiftNumber
starttime=`redis-cli hget $startstring starttime`
endtime=$now
length=$(($endtime - $starttime))
redis-cli hset Pool_Stats CurLength $length
dayslength=`echo "scale=3;$length / 86400" | bc -l`
TgtCoinPrice=`redis-cli hget Exchange_Rates <TARGET COIN NAME HERE>`
TotalEarned=0
TotalEarnedTgtCoin=0
redis-cli hset Pool_Stats CurDaysLength $dayslength
redis-cli del Pool_Stats:CurrentShift:WorkerBTC
redis-cli del Pool_Stats:CurrentShift:WorkerTgtCoin

# START CALCULATING COIN PROFIT FOR CURRENT ROUND - THIS ALSO CALCULATES WORKER EARNINGS MID SHIFT.
# PLEASE NOTE ALL COIN NAMES IN COIN_ALGO REDIS KEY MUST MATCH KEY NAMES IN EXCHANGE_RATES KEY CASE-WISE
while read line
do
        AlgoTotal=0
        AlgoTotalTgtCoin=0
        logkey2="Pool_Stats:CurrentShift:Algos"
        logkey2TgtCoin="Pool_Stats:CurrentShift:AlgosTgtCoin"
        echo "LOGKEY2: $logkey2"
        # loop through each coin for that algo
        while read CoinName
        do
                coinTotal=0
                coinTotalTgtCoin=0
                thiskey=$CoinName":balances"
                logkey="Pool_Stats:CurrentShift:Coins"
                logkeyTgtCoin="Pool_Stats:CurrentShift:CoinsTgtCoin"
                #Determine price for Coin
                coin2btc=`redis-cli hget Exchange_Rates $CoinName`
#               echo "$CoinName - $coin2btc"
                workersPerCoin=`redis-cli hlen $thiskey`
                if [ $workersPerCoin = 0 ]
                then
                        echo "do nothing" > /dev/null
                else

                        while read WorkerName
                        do
                                thisBalance=`redis-cli hget $thiskey $WorkerName`
                                thisEarned=`echo "scale=6;$thisBalance * $coin2btc" | bc -l`
                                coinTotal=`echo "scale=6;$coinTotal + $thisEarned" | bc -l`
                                AlgoTotal=`echo "scale=6;$AlgoTotal + $thisEarned" | bc -l`
                                TgtCoinEarned=`echo "scale=6;$thisEarned / $TgtCoinPrice" | bc -l`
                                coinTotalTgtCoin=`echo "scale=6;$coinTotalTgtCoin + $TgtCoinEarned" | bc -l`
                                AlgoTotalTgtCoin=`echo "scale=6;$AlgoTotalTgtCoin + $TgtCoinEarned" | bc -l`

#                               echo "$WorkerName earned $TgtCoinEarned from $CoinName"
                                redis-cli hincrbyfloat Pool_Stats:CurrentShift:WorkerTgtCoin $WorkerName $TgtCoinEarned
                                redis-cli hincrbyfloat Pool_Stats:CurrentShift:WorkerBTC $WorkerName $thisEarned
                        done< <(redis-cli hkeys $CoinName:balances)
                        redis-cli hset $logkey $CoinName $coinTotal
                        redis-cli hset $logkeyTgtCoin $CoinName $coinTotalTgtCoin
                        echo "$CoinName: $coinTotal"

                fi
        done< <(redis-cli hkeys Coin_Names_$line)
          redis-cli hset $logkey2 $line $AlgoTotal
        redis-cli hset $logkey2TgtCoin $line $AlgoTotalTgtCoin
TotalEarned=`echo "scale=6;$TotalEarned + $AlgoTotal" | bc -l`
TotalEarnedTgtCoin=`echo "scale=6;$TotalEarnedTgtCoin + $AlgoTotalTgtCoin" | bc -l`

done< <(redis-cli hkeys Coin_Algos)


# END CALCULATING COIN PROFITS FOR CURRENT SHIFT


# START CALCULATIN AVERAGE HASHRATES SO FAR THIS SHIFT
echo "Start: $starttime End: $endtime"
        AlgoCounter=0
        while read Algo
        do
                AlgoCounter=$(($AlgoCounter + 1))
                if [ $Algo = "sha256" ]
                then
                        Algo="sha256"
                fi
                AlgoHRTotal=0
                counter=0
                loopstring="Pool_Stats:AvgHRs:"$Algo
                while read HR
                do
                        IN=$HR
                        arrIN=(${IN//:/ })
                        amt=${arrIN[0]}
                        counter=`echo "$counter + 1" | bc`
                        AlgoHRTotal=`echo "$AlgoHRTotal + $amt" | bc -l`
               done< <(redis-cli zrangebyscore $loopstring $starttime $endtime)

                if [ $Algo = "sha" ]
                then
                        Algo="sha256"
                fi
                thisalgoAVG=`echo "scale=8;$AlgoHRTotal / $counter" |  bc -l`
                string="average_"$Algo
                redis-cli hset Pool_Stats:CurrentShift $string $thisalgoAVG
                string3="Pool_Stats:CurrentShift:Algos"
                thisalgoEarned=`redis-cli hget $string3 $Algo`
                thisalgoP=`echo "scale=8;$thisalgoEarned / $thisalgoAVG / $dayslength" | bc -l`
                string2="Profitability_$Algo"
                redis-cli hset Pool_Stats:CurrentShift $string2 $thisalgoP
                if [ $Algo = "keccak" ]
                then
                        thisalgoP=`echo "scale=8;$thisalgoP * 500" | bc -l`
                elif [ $Algo = "sha256" ]
                then
                        thisalgoP=`echo "scale=8;$thisalgoP * 100" | bc -l`
                elif [ $Algo = "x11" ]
                then
                        thisalgoP=`echo "scale=8;$thisalgoP * 4" | bc -l`
                else
                        echo "done" >/dev/null
                fi
                if [ -z "$thisalgoP" ]
                then
                        thisalgoP=0
                fi

                ProArr[$AlgoCounter]=$thisalgoP
                NameArr[$AlgoCounter]=$Algo
                redis-cli hset Pool_Stats:CurrentShift $string2 $thisalgoP

                echo "For Current Shift Algo $Algo had an average of $thisalgoAVG - profitability was $thisalgoP"
        done< <(redis-cli hkeys Coin_Algos)

                profitstring=${ProArr[1]}":"${ProArr[2]}":"${ProArr[3]}":"${ProArr[4]}":"${ProArr[5]}
                stringnames=${NameArr[1]}":"${NameArr[2]}":"${NameArr[3]}":"${NameArr[4]}":"${NameArr[5]}
redis-cli hset Pool_Stats:CurrentShift:Profitability $now $profitstring
redis-cli hset Pool_Stats:CurrentShift  NameString $stringnames
