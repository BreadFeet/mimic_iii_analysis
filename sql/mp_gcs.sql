-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Extract patients' Glasgow Coma Scale (GCS)

-----------------------
-- Background
-----------------------
-- GCS: Clinical scoring tool used to measure a person's level of consciousness, particularly after a brain injury. 
-- Scores range from 3 (deep coma) to 15 (fully awake), calculated by assessing three categories: 
-- Eye Opening (1-4), Verbal Response (1-5), and Motor Response (1-6).
-- Patients who can't speak due to inbutabion not unconsiousness, are flagged separately and assigned 15 score by convention.


drop table if exists mp_gcs cascade;
create table mp_gcs as

-----------------------
-- Pivot table
-----------------------
-- Extract only GCS related items (eye, verbal, motor response) from chartevents table 

with pvt as
(
	select co.icustay_id, ce.charttime
		, case when ce.itemid in (184, 220739) then 184
			when ce.itemid in (723, 223900) then 723
			when ce.itemid in (454, 223901) then 454 else ce.itemid end
			as itemid
		-- Verbal response: The pations with endotracheal tube/tracheostomy should be separated from no response 
		, case when ce.itemid = 723 and ce.value = '1.0 ET/Trach' then 0
			when ce.itemid = 223900 and ce.value = 'No Response-ETT' then 0 else valuenum end 
			as valuenum
	from  mp_cohort co inner join chartevents ce
		on co.icustay_id = ce.icustay_id
		and co.excluded = 0
	-- Carevue -> 184: Eye Opening, 454: Motor Response, 723: Verbal Response
	-- Metavision -> 220739: GCS-Eye Opening, GCS-Verbal Response, 223901: GCS-Motor Response
	where ce.itemid in (
		184, 454, 723, 223900, 223901, 220739
	    )
		-- There are many NULL in error column and NULL != 1 operation doesn't work
		and ce.error is distinct from 1
),

-----------------------
-- Base table
-----------------------
-- Pivot itemid into GCSEyes, GCSVerbal and GCSMotor columns and group by icustay_id and charttime

base as 
(
	select icustay_id, charttime
		-- Pivot itemid into different columns
		, max(case when itemid = 184 then valuenum else null end) as GCSEyes
		, max(case when itemid = 723 then valuenum else null end) as GCSVerbal
		, max(case when itemid = 454 then valuenum else null end) as GCSMotor
		-- Intubated patients will be flagged
		, case when max(case when itemid = 723 then valuenum else null end) = 0 then 1 else 0 end
			as EndoTrachFlag
		, row_number() over (partition by icustay_id order by charttime asc) as rn
	from pvt
	group by icustay_id, charttime
),

----------------------------
-- Glasgow Coma Scale table
----------------------------
-- Calculate GCS by comparing the current state (t) and the previous one (t-1)

gcs as (
	select b.*
		, b2.GCSeyes as GCSEyesPrev
		, b2.GCSverbal as GCSVerbalPrev
		, b2.GCSmotor as GCSMotorPrev
		-- GCS calculation
		, case when b.GCSVerbal = 0 then 15
			--- Limitation: only compare between the current and immediately preceeding one, not further lookback
			when b2.GCSVerbal = 0 and b.GCSVerbal is null then 15
			--- If previously they were intubated but not now, do not use previous GCS values
			when b2.GCSVerbal = 0
			 then coalesce(b.GCSEyes, 4)  + coalesce(b.GCSVerbal, 5) + coalesce(b.GCSMotor, 6)
			--- Otherwise, add up score normally, imputing previous value if NULL at current time 
			else coalesce(b.GCSEyes, b2.GCSEyes, 4) 
				+ coalesce(b.GCSVerbal, b2.GCSVerbal, 5) 
		 		+ coalesce(b.GCSMotor, b2.GCSMotor, 6) end
		 	as GCS
	from base b left join base b2
		on b.icustay_id = b2.icustay_id
		and b.rn = b2.rn + 1
		-- The difference between the adjacent charttimes should be less than 6 hours
		and b.charttime - interval '6' hour < b2.charttime
),


-----------------------
--  GCS staging table
-----------------------
-- Add hours after ICU admission, carry forward GCS components, add how many of component measurements

gcs_stg as (
	select gcs.icustay_id
		, charttime 
		, ceil(extract(epoch from charttime - co.intime)/60.0/60.0)::smallint as hr
		, GCS
		, coalesce(GCSEyes, GCSEyesPrev) as GCSEyes
		, coalesce(GCSVerbal, GCSVerbalPrev) as GCSVerbal
		, coalesce(GCSMotor, GCSMotorPrev) as GCSMotor
		-- How many of 3 GCS components has both current and previous measurement (0 - 3)
		, case when coalesce(GCSEyes, GCSEyesPrev) is null then 0 else 1 end
			+ case when coalesce(GCSVerbal, GCSVerbalPrev) is null then 0 else 1 end 
			+ case when coalesce(GCSMotor, GCSMotorPrev) is null then 0 else 1 end
			as components_measured
		, EndoTrachFlag
	from gcs inner join mp_cohort co
		on gcs.icustay_id = co.icustay_id
		and co.excluded = 0
),

-----------------------
--  GCS priority table
-----------------------
-- Set the priority among the same icustay_id and hr
-- Priority: (1) complete data, (2) no inbubation, (3) lowest GCS (more serious state), (4) recent charttime

gcs_priority as (
	select icustay_id
		, hr
		, GCS
		, GCSEyes
		, GCSVerbal
		, GCSMotor
		, EndoTrachFlag
		, row_number() over (
			partition by icustay_id, hr 
			order by components_measured desc, EndoTrachFlag asc, GCS asc, charttime desc)
			as rn
	from gcs_stg
)

-----------------------
--  Main query
-----------------------
-- Only pick the highest priorities

select icustay_id
	, hr
	, GCS
	, GCSEyes
	, GCSVerbal
	, GCSMotor
	, EndoTrachFlag
from gcs_priority
where rn = 1
order by icustay_id, hr;