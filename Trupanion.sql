SET NOEXEC ON
--SET NOEXEC OFF
-------------------
--Import tables into SQL SERVER
-------------------
drop table if exists petdata
drop table if exists claimdata

--Create schema
Create table petdata (
PetId int,
EnrollDate date,
CancelDate date,
Species varchar(100),
Breed varchar(100),
AgeAtEnroll varchar(100))

Create table claimdata (
ClaimId int,
PetID int,
ClaimDate date,
ClaimAmount float)

truncate table petdata
truncate table claimdata

--Import Data
--Note, eliminated filepath here because of possible confidentiality
BULK INSERT PetData from 'petdata.csv' with (FIELDTERMINATOR = ',',FIRSTROW=2)
BULK INSERT ClaimData from 'claimdata.csv' with (FIELDTERMINATOR = ',',FIRSTROW=2)

------------------
--Feature Engineering
------------------

--Check Dates for PetData/ClaimData
select min(enrolldate) from petdata--2009-11-20
select min(CancelDate) from petdata--2010-01-13
select max(enrolldate) from petdata--2019-11-27
select max(CancelDate) from petdata--2019-11-27

select min(ClaimDate) from claimdata--2010-01-06
select max(ClaimDate) from claimdata--2019-06-30

--Get Pet Birthdates
--Since we have ranges, get mininum possible birthdate and maximum possible birthdate
alter table petdata add MinBirthDate date
alter table petdata add MaxBirthDate date
alter table petdata add YearsAtEnroll int
GO
SELECT COUNT(*), AgeAtEnroll from petdata group by AgeAtEnroll

update petdata set YearsAtEnroll = LEFT(AgeAtEnroll, charindex(' ', AgeAtEnroll) - 1) where AgeAtEnroll like '%year%'

update petdata set maxBirthDate = DATEADD(year,YearsAtEnroll*-1,EnrollDate)
update petdata set minBirthDate = DATEADD(year,(1+YearsAtEnroll)*-1,EnrollDate)

update petdata set minBirthDate = DATEADD(month,-12,EnrollDate) where AgeAtEnroll = '8 weeks to 12 months old'
update petdata set maxBirthDate = DATEADD(week,-8,EnrollDate) where AgeAtEnroll = '8 weeks to 12 months old'

update petdata set minBirthDate = DATEADD(week,-7,EnrollDate) where AgeAtEnroll = '0-7 weeks old'
update petdata set maxBirthDate = EnrollDate where AgeAtEnroll = '0-7 weeks old'

------------------
--Get PetData split up by month
------------------
--Get all months and year between 2010-01-01 and 2019-06-30
drop table if exists months

DECLARE @Date DATE = '2010-01-01'
;WITH GetMonths as
(
    SELECT   [MonthName]    = DATENAME(mm ,@Date)  
            ,[MonthNumber]  = DATEPART(mm ,@Date)  
            ,[MonthYear]    = DATEPART(yy ,@Date)
			,MinDate = @Date
			,MaxDate = EOMONTH(@Date)
            ,NextRow        = DATEADD(MONTH, 1, @Date)
			,DaysInMonth = DAY(EOMONTH(@Date))
			,TotalDays = DATEDIFF(Day,@Date,@Date)
    UNION ALL
    SELECT   DATENAME(mm ,NextRow)
            ,DATEPART(mm ,NextRow)
            ,DATEPART(yy ,NextRow)
			,NextRow
			,EOMONTH(NEXTROW)
            ,DATEADD(MONTH, 1, NextRow)
			,DAY(EOMONTH(NextRow))
			,DATEDIFF(Day,@Date,NextRow)
    FROM    GetMonths
)
SELECT top 200 *
		into Months
FROM GetMonths
OPTION(MAXRECURSION 0)

delete from Months where MonthYear > 2019
delete from Months where MonthYear = 2019 and MonthNumber > 7

--Combine Pet Data with Months
drop table if exists MonthsPetData

select * into MonthsPetData from months m full outer join petdata p on MaxDate >= EnrollDate and (CancelDate >= MinDate or CancelDate is null)

alter table MonthsPetData add DaysInPolicy int
GO

-----------------
--Feature Engineering for PetData by Month
-----------------

--Get Days in Policy for each pet-month combination (most of the time it's the same as the number of days in month, but have to adjust for enroll/cancel date
update MonthsPetData set DaysInPolicy = DaysInMonth
update MonthsPetData set DaysInPolicy = DaysInPolicy + DATEDIFF(DAY,EnrollDate,MinDate) where EnrollDate > MinDate
update MonthsPetData set DaysInPolicy = DaysInPolicy + DATEDIFF(DAY,MaxDate,CancelDate) where MaxDate > CancelDate

--Get possible age ranges for each pet-month combination
alter table MonthsPetData add MinAgeInDays int
alter table MonthsPetData add MaxAgeInDays int
GO
/*Selection to make sure I get date diff right 
select *, DATEDIFF(DAY,MaxBirthDate,MinDate), DATEDIFF(DAY,MinBirthDate,MaxDate), 
DATEDIFF(DAY,MaxBirthDate,MaxDate),
DATEDIFF(DAY,MinBirthDate,MinDate)
from MonthsPetData where DATEDIFF(DAY,MaxBirthDate,MinDate) < 0
*/
update MonthsPetData set MaxAgeInDays = DATEDIFF(DAY,MinBirthDate,MaxDate)
update MonthsPetData set MinAgeInDays = DATEDIFF(DAY,MaxBirthDate,MinDate)

--Get number of months and days from start of policy
alter table MonthsPetData add TotalDaysInPolicy int
alter table MonthsPetData add TotalMonthsInPolicy int
GO
update MonthsPetData set TotalMonthsInPolicy = DATEDIFF(MONTH,EnrollDate,MaxDate)
update MonthsPetData set TotalDaysInPolicy = DATEDIFF(DAY,EnrollDate,MaxDate)

drop table if exists #ClaimDataGroup, #PastClaims

--Get Number of Claims and Claim Amounts for month-pet combiatino
select PetID, count(*) as NumberOfClaims, Month(ClaimDate) as ClaimMonth, year(ClaimDate) as ClaimYear, sum(ClaimAmount) as ClaimAmount, cast(cast(Month(claimDate) as varchar)+'/1/'+cast(Year(ClaimDate) as varchar) as date) as ClaimDate
into #ClaimDataGroup
from claimdata
GROUP BY PetID, Month(ClaimDate), year(ClaimDate)

--select * from #ClaimDataGroup c join MonthsPetData m on MonthNumber = ClaimMonth and MonthYear=ClaimYear and c.PetID = m.PetID
----------------------------------
--Get Claim Amount (dependent variable)
----------------------------------
alter table MonthsPetData add ClaimAmount float
GO
update m set ClaimAmount = c.claimAmount from
#ClaimDataGroup c join MonthsPetData m on MonthNumber = ClaimMonth and MonthYear=ClaimYear and c.PetID = m.PetID

------------------------------
--Get Previous Months Claim Amount for each pet
------------------------------
select c.PetID, c.ClaimAmount, c.ClaimDate, m.minDate, DateDIFF(Month,c.ClaimDate,m.MinDate) as MonthDiff, NumberOfClaims
into #PastClaims
from #ClaimDataGroup c join MonthsPetData m on c.PetID = m.PetId and m.mindate > c.ClaimDate

drop table if exists ClaimRanking

------------------------------
--Get Size and how long ago each claim for
------------------------------
select c.PetID, c.ClaimDate, c.ClaimAmount, m.MinDate, ROW_NUMBER() over (PARTITION BY c.PetID, m.Mindate ORDER by ClaimDate desc, ClaimID) as ClaimRank, 
DATEDIFF(Day,ClaimDate, MinDate) as DateDif
into ClaimRanking
from claimdata c join MonthsPetData m on c.PetID = m.PetID and m.mindate > c.ClaimDate

--select * from #PastClaims order by PetID, monthdiff

--Get Claim Amounts from the past
alter table MonthsPetData add ClaimAmountPast float
alter table MonthsPetData add ClaimAmountAverage float
alter table MonthsPetData add ClaimNumber float
alter table MonthsPetData add ClaimAverageSize float
GO
--Get total of all claims in the past
update MonthsPetData set ClaimAmountPast = t.ClaimAmountPast from (
select sum(claimamount) as ClaimAmountPast, minDate, PetID from #PastClaims p group by Mindate, PetID) t 
join MonthsPetData m on t.PetID = m.PetID and t.MinDate = m.Mindate

--Get Average claim amount per month of claims in the past
update MonthsPetData set ClaimAmountAverage = ClaimAmountPast / cast(TotalMonthsInPolicy as float)

--Get Number of Claims in the past
update MonthsPetData set ClaimNumber = t.ClaimNumber from (
select sum(NumberOfClaims) as ClaimNumber, minDate, PetID from #PastClaims p group by Mindate, PetID) t 
join MonthsPetData m on t.PetID = m.PetID and t.MinDate = m.Mindate

--Get Average Size for claims in the past
update MonthsPetData set ClaimAverageSize = ClaimAmountPast / ClaimNumber

/*
update MonthsPetData set ClaimAmountPastMonth = t.ClaimAmountPast from (
select sum(claimamount) as ClaimAmountPast, minDate, PetID from #PastClaims p where MonthDiff = 1 group by Mindate, PetID) t 
join MonthsPetData m on t.PetID = m.PetID and t.MinDate = m.Mindate
*/

--Get total of all claims in the past X months (between 1 and 12)
--Get number of all claims in the past X months (between 1 and 12)
--Get average size of all claims in the past X months (between 1 and 12)
--Get % change between Average Claim Amount overall and Average Claim Amount in the past 
DECLARE @SQL VARCHAR(MAX)
DECLARE @loopcounter int = 1
WHILE @loopcounter <= 12
BEGIN
SET @SQL = 'Alter table MonthsPetData add ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore float
Alter table MonthsPetData add ClaimNumberPast'+cast(@loopcounter as varchar)+'MonthOrMore int
Alter table MonthsPetData add ClaimSizePast'+cast(@loopcounter as varchar)+'MonthOrMore float
Alter table MonthsPetData add ClaimDeltaPast'+cast(@loopcounter as varchar)+'MonthOrMore float
'
EXEC(@SQL)
SET @SQL ='update MonthsPetData set ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore = t.ClaimAmountPast from (
select sum(claimamount) as ClaimAmountPast, minDate, PetID from #PastClaims p where MonthDiff <= '+cast(@loopcounter as varchar)+' group by Mindate, PetID) t 
join MonthsPetData m on t.PetID = m.PetID and t.MinDate = m.Mindate

update MonthsPetData set ClaimNumberPast'+cast(@loopcounter as varchar)+'MonthOrMore = t.ClaimNumber from (
select sum(NumberOfClaims) as ClaimNumber, minDate, PetID from #PastClaims p where MonthDiff <= '+cast(@loopcounter as varchar)+' group by Mindate, PetID) t 
join MonthsPetData m on t.PetID = m.PetID and t.MinDate = m.Mindate

update MonthsPetData set ClaimSizePast'+cast(@loopcounter as varchar)+'MonthOrMore 
= ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore / 
cast(ClaimNumberPast'+cast(@loopcounter as varchar)+'MonthOrMore as float)
from MonthsPetData
where ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore is not null

update MonthsPetData set ClaimDeltaPast'+cast(@loopcounter as varchar)+'MonthOrMore 
= ((ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore /
cast('+cast(@loopcounter as varchar)+' as float))-ClaimAmountAverage)
/ cast(ClaimAmountAverage as float)
from MonthsPetData
where ClaimAmountPast'+cast(@loopcounter as varchar)+'MonthOrMore is not null
'
PRINT(@SQL)
EXEC (@SQL)
SET @loopcounter = @loopcounter + 1
END--7m

--Get Past 5 Claim Amounts and how long ago they were from each month-pet combination
DECLARE @SQL2 VARCHAR(MAX)
DECLARE @loopcounter2 int = 1
WHILE @loopcounter2 <= 5
BEGIN
SET @SQL2 = 'Alter table MonthsPetData add PastAmount'+cast(@loopcounter2 as varchar)+'Claim float
Alter table MonthsPetData add PastDay'+cast(@loopcounter2 as varchar)+'Claim int
'
EXEC(@SQL2)
SET @SQL2 ='update MonthsPetData set PastAmount'+cast(@loopcounter2 as varchar)+'Claim = c.ClaimAmount from 
ClaimRanking c join MonthsPetData m on c.PetID = m.PetID and c.MinDate = m.MinDate and ClaimRank = '+cast(@loopcounter2 as varchar)+'

update MonthsPetData set PastDay'+cast(@loopcounter2 as varchar)+'Claim = c.DateDif from 
ClaimRanking c join MonthsPetData m on c.PetID = m.PetID and c.MinDate = m.MinDate and ClaimRank = '+cast(@loopcounter2 as varchar)+'
'
PRINT(@SQL2)
EXEC (@SQL2)
SET @loopcounter2 = @loopcounter2 + 1
END--7m

--Export MonthsPetData
select * from MonthsPetData order by claimamount desc

--Export MonthsPetData (Internal Export Proc)
exec SimpleBCP @SQLCommand = 'Select * from MonthsPetData', @FileLocation = 'C:\Trupanion\MonthsPetData.txt'