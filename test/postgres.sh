#!/bin/bash

# script to run a simple load test for a serial key:
# 1. Generate 1000 rows with known distribution
# 2. Count rows - should be 1000
# 3. Count rows where str column = "a" - should be 100
# 4. Update all rows where str column = "a"
# 5. Count rows where str column = "a" - should be 0
# 6. Delete all rows where int column < 101
# 7. Count all rows - should be 900
# 8. Delete all rows where 1=1
# 7. Count all rows - should be 0

# createuser -d -r -s root
# createuser -d -r -s btest

testcount=0
passcount=0
errorcount=0

SQLCMD0='psql -w -h localhost -p 5432 -U btest -d batchertestdb '
SQLCMD='psql -w -h localhost -p 5432 -U btest -d batchertestdb -t -A -c '

comp () {

	if [ $2 != $3 ]
	then
		errorcount=$(( errorcount + 1 ))
		printf "F($1: expected $2, got $3)"
	else
		passcount=$(( passcount + 1 ))
		printf "."
		# printf "($1: expected $2, got $3)"
	fi
	testcount=$(( testcount + 1 ))

}

printf "Preparing load script..."
echo "CREATE TABLE IF NOT EXISTS serialtest (pk SERIAL NOT NULL PRIMARY KEY, intcol INT, strcol VARCHAR(20));" > /tmp/$$
echo "GRANT ALL ON serialtest TO PUBLIC;" >> /tmp/$$

for i in {1..1000}
do
	if [ $i -le 100 ]
	then
		s='a'
	else
		s='b'
	fi
	echo "INSERT INTO serialtest (intcol, strcol) VALUES ($i, '$s');" >> /tmp/$$
done

# same test but with a UUID key
echo "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE TABLE IF NOT EXISTS uuidtest (pk UUID DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY, intcol INT, strcol VARCHAR(20));" >> /tmp/$$
echo "GRANT ALL ON uuidtest TO PUBLIC;" >> /tmp/$$

for i in {1..1000}
do
	if [ $i -le 100 ]
	then
		s='a'
	else
		s='b'
	fi
	echo "INSERT INTO uuidtest (intcol, strcol) VALUES ($i, '$s');" >> /tmp/$$
done

# same test but with a composite key
echo "CREATE TABLE IF NOT EXISTS compositetest (pk1 INT NOT NULL, pk2 VARCHAR(10) NOT NULL, intcol INT, strcol VARCHAR(20), PRIMARY KEY(pk1, pk2));" >> /tmp/$$
echo "GRANT ALL ON compositetest TO PUBLIC;" >> /tmp/$$

for i in {1..1000}
do
	if [ $i -le 100 ]
	then
		s='a'
	else
		s='b'
	fi
	echo "INSERT INTO compositetest (pk1, pk2, intcol, strcol) VALUES ($i, '$s', $i, '$s');" >> /tmp/$$
done

echo "done"
printf "Populating test database..."

$SQLCMD0 < /tmp/$$ > /dev/null 2>&1
echo "ALTER USER btest PASSWORD 'btest';
GRANT ALL ON DATABASE batchertestdb TO PUBLIC;" > /tmp/$$

$SQLCMD0 < /tmp/$$ > /dev/null 2>&1


echo "done"
printf "Starting tests"

exptot=1000
expa=100

sertot=$( $SQLCMD "SELECT COUNT(1) FROM serialtest;" )
comp "Initial serial total" $exptot $sertot
sera=$( $SQLCMD "SELECT COUNT(1) FROM serialtest WHERE strcol = 'a';" )
comp "Initial serial a" $expa $sera
uidtot=$( $SQLCMD "SELECT COUNT(1) FROM uuidtest;" )
comp "Initial UUID total" $exptot $uidtot
uida=$( $SQLCMD "SELECT COUNT(1) FROM uuidtest WHERE strcol = 'a';" )
comp "Initial UUID a" $expa $uida
cmptot=$( $SQLCMD "SELECT COUNT(1) FROM compositetest;" )
comp "Initial composite total" $exptot $cmptot
cmpa=$( $SQLCMD "SELECT COUNT(1) FROM compositetest WHERE strcol = 'a';" )
comp "Initial composite a" $expa $cmpa

exptot=900
expa=0

../batcher update -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table serialtest -set "strcol='b'" -user btest -where "strcol='a'" -execute

sera=$( $SQLCMD "SELECT COUNT(1) FROM serialtest WHERE strcol = 'a';" )
comp "Updated serial a" $expa $sera

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table serialtest -user btest -where "intcol<101" -execute

sertot=$( $SQLCMD "SELECT COUNT(1) FROM serialtest;" )
comp "Small delete serial total" $exptot $sertot

../batcher update -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -set "strcol='b'"  -table uuidtest -user btest -where "strcol='a'" -execute

uida=$( $SQLCMD "SELECT COUNT(1) FROM uuidtest WHERE strcol = 'a';" )
comp "Updated UUID a" $expa $uida

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table uuidtest -user btest -where "intcol<101" -execute

uidtot=$( $SQLCMD "SELECT COUNT(1) FROM uuidtest;" )
comp "Small delete UUID total" $exptot $uidtot

../batcher update -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -set "strcol='b'"  -table compositetest -user btest -where "strcol='a'" -execute

cmpa=$( $SQLCMD "SELECT COUNT(1) FROM compositetest WHERE strcol = 'a';" )
comp "Updated composite a" $expa $cmpa

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table compositetest -user btest -where "intcol<101" -execute

cmptot=$( $SQLCMD "SELECT COUNT(1) FROM compositetest;" )
comp "Small delete composite total" $exptot $cmptot

exptot=0

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table serialtest -user btest -where "1=1" -execute

sertot=$( $SQLCMD "SELECT COUNT(1) FROM serialtest;" )
comp "Full delete serial total" $exptot $sertot

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table uuidtest -user btest -where "1=1" -execute

uidtot=$( $SQLCMD "SELECT COUNT(1) FROM uuidtest;" )
comp "Full delete UUID total" $exptot $uidtot

../batcher delete -concurrency 4 -database batchertestdb -dbtype postgres -host localhost -opts "sslmode=disable" -password btest -portnum 5432 -table compositetest -user btest -where "1=1" -execute

cmptot=$( $SQLCMD "SELECT COUNT(1) FROM compositetest;" )
comp "Full delete composite total" $exptot $cmptot

rm /tmp/$$

echo "done"
echo "PostgreSQL Tests: $testcount Passed: $passcount Failed: $errorcount"
exit $errorcount
