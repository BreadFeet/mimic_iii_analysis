-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Combine all tables created to get all features at every ICU hour for each patient

drop table if exists mp_data cascade;
create table mp_data as

select 
	  mp.subject_id, mp.hadm_id, mp.icustay_id, mp.hr
	, vi. HeartRate
	, vi.SysBP
	, vi.DiaBP
	, vi.MeanBP
	, vi.RespRate
	, gcs.GCS
	, gcs.GCSEyes
	, gcs.GCSVerbal
	, gcs.GCSMotor
	, gcs.EndoTrachFlag
	, bg.pO2 as bg_pO2
	, bg.pCO2 as bg_pCO2
	, bg.PaO2FiO2Ratio as bg_PaO2FiO2Ratio
	, bg.pH as bg_pH
	, bg.BaseExcess as bg_BaseExcess
	, bg.TotalCO2 as bg_TotalCO2
	, bg.CarboxyHemoglobin as bg_CarboxyHemoglobin
	, bg.MetHemoglobin as bg_MetHemoglobin
	, lab.AnionGap
	, lab.Albumin
	, lab.Bands
	-- Lab results are prioritised.
	-- lab.bicarbonate: from labevents [chemistry], bg.carbonate: labevents [blood gas]
	, coalesce(lab.Bicarbonate, bg.Bicarbonate) as Bicarbonate
	, lab.Bilirubin
	, lab.BUN
	, bg.Calcium
	, coalesce(lab.Chloride, bg.Chloride) as Chloride
	, lab.Creatinine
	-- lab.glucose: from labevents [chemistry], bg.glucose: from labevents [blood gas]
	, coalesce(lab.Glucose, bg.Glucose, vi.Glucose) as Glucose
	, coalesce(lab.Hematocrit, bg.Hematocrit) as Hematocrit
	, coalesce(lab.Hemoglobin, bg.Hemoglobin) as Hemoglobin
	, lab.INR
	, coalesce(lab.Lactate, bg.Lactate) as Lactate
	, lab.Platelet
	, coalesce(lab.Potassium, bg.Potassium) as Potassium	 
	, lab.PTT
	, coalesce(lab.Sodium, bg.Sodium) as Sodium
	, coalesce(bg.SO2, vi.SpO2) as SpO2
	-- bg.temperature: from labevents, vi.temperature: from chartevents
	, coalesce(bg.Temperature, vi.TempC) as TempC
	, lab.WBC
	, uo.UrineOutput
	
from mp_hourly_cohort mp 
	-- All the 'hr's are calculated against 
    left join mp_vital vi on mp.icustay_id = vi.icustay_id and mp.hr = vi.hr    -- hr: chartevents.charttime
	left join mp_gcs gcs on mp.icustay_id = gcs.icustay_id and mp.hr = gcs.hr   -- hr: chartevents.charttime
	left join mp_uo uo on mp.icustay_id = uo.icustay_id and mp.hr = uo.hr       -- hr: outputevents.charttime
	left join mp_bg_art bg on mp.hadm_id = bg.hadm_id and mp.hr = bg.hr         -- hr: labevents.charttime
	left join mp_lab lab on mp.hadm_id = lab.hadm_id and mp.hr = lab.hr         -- hr: labevents.charttime
order by mp.subject_id, mp.hadm_id, mp.icustay_id, mp.hr;