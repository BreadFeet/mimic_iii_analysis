-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Extract patients' vital signs, eg. heart rate

drop table if exists mp_vital cascade;
create table mp_vital as

-----------------------
-- Chart events table
-----------------------

with ce as 
(
	select co.icustay_id
		, ceil(extract(epoch from ce.charttime - co.intime)/60.0/60.0)::smallint as hr
		-- Add in some sanity checks on the values & Pivot itemid
		, case when itemid in (211, 220045) and valuenum > 0 and valuenum < 300 then valuenum else null end as HeartRate
		, case when itemid in (51, 442, 455, 6701, 220179, 220050) and valuenum > 0 and valuenum < 400 then valuenum else null end as SysBP
		, case when itemid in (8368, 8440, 8441, 8555, 220180, 220051) and valuenum >0 and valuenum <300 then valuenum else null end as DiaBP
		, case when itemid in (52, 6702, 443, 456, 220052, 220181, 225312) and valuenum > 0 and valuenum < 300 then valuenum else null end as MeanBP
		, case when itemid in (618, 615, 220210, 224690) and valuenum >0 and valuenum < 70 then valuenum else null end as RespRate
		, case when itemid in (646, 220277) and valuenum > 0 and valuenum <= 100 then valuenum else null end as SpO2
		, case when itemid in (807, 811, 1529, 3745, 3744, 225664, 220621, 226537) and valuenum > 0 then valuenum else null end as Glucose
		, case when itemid in (223761, 678) and valuenum > 70 and valuenum < 120 then (valuenum - 32) / 1.8  -- Convert to Celsius
			when itemid in (223762, 676) and valuenum > 10 and valuenum < 50 then valuenum else null end as TempC
	from mp_cohort co inner join chartevents ce
		on co.icustay_id = ce.icustay_id
		and co.excluded = 0
	where ce.error is distinct from 1
		and ce.itemid in (
			-- HEART RATE
	        211,      -- Heart Rate
	        220045,   -- Heart Rate
	        -- SYSTOLIC
	        51,       -- Arterial BP [Systolic]
	        442,      -- Manual BP [Systolic]
	        455,      -- NBP [Systolic] (non-invasive BP)
	        6701,     -- Arterial BP #2 [Systolic]
	        220179,   -- Non Invasive Blood Pressure systolic
	        220050,   -- Arterial Blood Pressure systolic
	        -- DIASTOLIC
	        8368,     -- Arterial BP [Diastolic]
	        8440,     -- Manual BP [Diastolic]
	        8441,     -- NBP [Diastolic]
	        8555,     -- Arterial BP #2 [Diastolic]
	        220180,   -- Non Invasive Blood Pressure diastolic
	        220051,   -- Arterial Blood Pressure diastolic
	        -- MEAN ARTERIAL PRESSURE
	        52,       -- Arterial BP Mean
	        6702,     -- Arterial BP Mean #2
	        443,      -- Manual BP Mean(calc)
	        456,      -- NBP Mean
	        220052,   -- Arterial Blood Pressure mean
	        220181,   -- Non Invasive Blood Pressure mean
	        225312,   -- ART BP mean
	        -- RESPIRATORY RATE
	        618,      -- Respiratory Rate
	        615,      -- Resp Rate (Total)
	        220210,   -- Respiratory Rate
	        224690,   -- Respiratory Rate (Total)
	        -- SpO2, peripheral
	        646,      -- SpO2
	        220277,   -- O2 saturation pulseoxymetry
	        -- GLUCOSE, both lab and fingerstick
	        807,      -- Fingerstick Glucose
	        811,      -- Glucose (70-105)
	        1529,     -- Glucose
	        3745,     -- BloodGlucose (quick admit)
	        3744,     -- Blood Glucose (chemistry)
	        225664,   -- Glucose finger stick
	        220621,   -- Glucose (serum)
	        226537,   -- Glucose (whole blood)
	        -- TEMPERATURE
	        223762,   -- Temperature Celsius
	        676,      -- Temperature C
	        223761,   -- Temperature Fahrenheit
	        678       -- Temperature F
		)
)	
	
-----------------------
-- Main query
-----------------------
-- Calculate average vital values per icustay_id and hr

select icustay_id, hr
	, avg(HeartRate) as HeartRate
	, avg(SysBP) as SysBP
	, avg(DiaBP) as DiaBP
	, avg(MeanBP) as MeanBP
	, avg(RespRate) as RespRate
	, avg(SpO2) as SpO2
	, avg(Glucose) as Glucose
	, avg(TempC) as TempC
from ce
group by icustay_id, hr
order by icustay_id, hr;