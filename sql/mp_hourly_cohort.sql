-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Remove exclusions from mp_cohort and generate sequence of ICU hours per patient.
-- Explode each ICU stay into one row per hour, creating a hour-by-hour grid for later time-series. 

drop table if exists mp_hourly_cohort cascade;
create table mp_hourly_cohort as
select 
	subject_id, hadm_id, icustay_id
	-- -24 to include the 24 hours before the ICU intime, to later capture pre-ICU data
	, generate_series(-24, ceil(extract(epoch from (outtime - intime))/60.0/60.0)::INTEGER) as hr
from mp_cohort
where excluded = 0
order by subject_id, hadm_id, icustay_id;