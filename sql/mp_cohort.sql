-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Create table for patient cohort

-----------------------
-- Background
-----------------------
-- Heart rate (211, 220045) chosen because it's monitored on nearly all ICU patients
-- regardless of diagnosis, so it's used as a proxy for actual monitoring start/end time.
-- A small number of stays (e.g. very short ICU stay) have no heart rate recorded,
-- so they end up with null intime_hr/outtime_hr and get dropped later via inner join.

drop table if exists mp_cohort cascade;
create table mp_cohort as

-----------------------
-- Chart event table
-----------------------
-- One row per icustay_id, charttime min/max rounded up to the hour for heart rate events
-- icustays.intime/outtime can be administratively inaccurate, so it's to replace them with actual heart-rate charttime bounds

with ce as 
(
	select ce.icustay_id
		-- ceiling this to the nearest hour
		, date_trunc('hour', min(charttime) + interval '59' minute) as intime_hr
		, date_trunc('hour', max(charttime) + interval '59' minute) as outtime_hr
	from icustays icu inner join chartevents ce
		on icu.icustay_id = ce.icustay_id
		-- this handles some fuzziness associated with ICU administrative intime/outtime
		and icu.intime - interval '12' hour < ce.charttime 
		and icu.outtime + interval '12' hour > ce.charttime 
	-- itemid: 211 - heart rate in Carevue, 220045 - heart rate in Metavision
	where ce.itemid in (211, 220045)
	group by ce.icustay_id
),

-----------------------
-- ICU table
-----------------------
-- Insert the newly calculated intime, outtime into icustays table; only icustay_id with heart rate event will get this new values
-- ICU stays is ordered chronologically per patient

icu as
(
	select icustays.subject_id, ce.icustay_id
		, row_number() over (partition by icustays.subject_id order by ce.intime_hr) as icustay_num
	from icustays left join ce
		using (icustay_id)
)

-----------------------
-- Main query
-----------------------
select 
	ie.subject_id, ie.hadm_id, ie.icustay_id, ie.dbsource
	, ce.intime_hr as intime, ce.outtime_hr as outtime 
	, round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) as age
	, pat.gender
	, adm.ethnicity
	, adm.admission_type
	, icu.icustay_num
	
	-- Outcomes
	, adm.hospital_expire_flag, pat.expire_flag
	, case when pat.dod <= adm.admittime + interval '30' day then 1 else 0 end 
		as thirtyday_expire_flag
	, ie.los as icu_los
	, extract(epoch from (adm.dischtime - adm.admittime))/60.0/60.0/24.0 as hosp_los
	--- When patients died in the hospital
	, ceil(extract(epoch from (adm.deathtime - ce.intime_hr))/60.0/60.0) as hosp_deathtime_hours
	--- Regardless patients died in or outside of the hospital
	, ceil(extract(epoch from (pat.dod - intime))/60.0/60.0) as deathtime_hours
	, adm.deathtime as deathtime_check
	
	-- Exclusions
	-- Below flags are used to summarize patients excluded for reporting purposes
	, case when round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) <= 16 
		or round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) > 89 then 1 else 0 end
		as exclusion_adult
	, case when adm.has_chartevents_data = 0 then 1
		when ie.intime is null then 1
		when ie.outtime is null then 1
		when ce.intime_hr is null then 1
		when ce.outtime_hr is null then 1 else 0 end
		as exclusion_valid_data
	, case when (ce.outtime_hr - ce.intime_hr) <= interval '4' hour then 1 else 0 end
		as exclusion_short_stay_4hr
	, case when (ce.outtime_hr - ce.intime_hr) <= interval '1' hour then 1 else 0 end
		as exclusion_short_stay_1hr
	, case when (adm.deathtime is not null and lower(diagnosis) like '%organ doner%')
		or (adm.deathtime is not null and lower(diagnosis) like '%doner account%') then 1 else 0 end
		as exclusion_organ_donor
	--- Below is the combination of all the preceding exclusions for execution purposes
	, case when round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) <= 16 
		or round((cast(adm.admittime as date) - cast(pat.dob as date)) / 365.242, 4) > 89 then 1
		when adm.has_chartevents_data = 0 then 1
		when ie.intime is null then 1
		when ie.outtime is null then 1
		when ce.intime_hr is null then 1
		when ce.outtime_hr is null then 1
		when (ce.outtime_hr - ce.intime_hr) <= interval '1' hour then 1 
		when (adm.deathtime is not null and lower(diagnosis) like '%organ doner%')
		or (adm.deathtime is not null and lower(diagnosis) like '%doner account%') then 1 else 0 end
		as excluded
from icustays ie inner join admissions adm
	on ie.hadm_id = adm.hadm_id
	inner join patients pat
	on ie.subject_id = pat.subject_id 
	inner join icu
	using (icustay_id)
	left join ce
	on ie.icustay_id = ce.icustay_id
order by ie.subject_id, icu.icustay_num;