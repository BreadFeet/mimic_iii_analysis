-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Extract patients' blood gas analysis and chemistry values

-----------------------
-- Background
-----------------------
-- FiO2 (Fraction of Inspired Oxygen) set: Set value in ventilator by healthcare professioanal
-- FiO2 measured: Actual oxygen measurements delivered to patients

-- SpO2 calculated by avg and FiO2 by max in a group; if there where more than one value in SpO2, 
-- both are meaningful separated values and should be avaraged. In FiO2, try to pick one meaningful
-- value out of NULLs with max.

-- The coefficients & average values and correction terms for null values imputation are referenced from the source.

-----------------------------------------------------------------
-- Blood Gas table
-----------------------------------------------------------------
-- Blood gas analyser results on blood only
-- This operation is on labevents table

drop table if exists mp_bg cascade;
create table mp_bg as

select hadm_id, charttime
	, max(case when itemid = 50800 then value else null end) as Specimen
	, avg(case when itemid = 50801 and valuenum > 0 then valuenum else null end) as AADO2   -- Alveola-arterial Oxygen Gradient
	, avg(case when itemid = 50802 and valuenum > 0 then valuenum else null end) as BaseExcess
	, avg(case when itemid = 50803 and valuenum > 0 then valuenum else null end) as Bicarbonate
	, avg(case when itemid = 50804 and valuenum > 0 then valuenum else null end) as TotalCO2
	, avg(case when itemid = 50805 and valuenum > 0 then valuenum else null end) as CarboxyHemoglobin
	, avg(case when itemid = 50806 and valuenum > 0 then valuenum else null end) as Chloride
	, avg(case when itemid = 50808 and valuenum > 0 then valuenum else null end) as Calcium
	, avg(case when itemid = 50809 and valuenum > 0 then valuenum else null end) as Glucose
	, avg(case when itemid = 50810 and valuenum <=100 then valuenum else null end) as Hematocrit
	, avg(case when itemid = 50811 and valuenum > 0 then valuenum else null end) as Hemoglobin
	, max(case when itemid = 50812 then value else null end) as Intubated
	, avg(case when itemid = 50813 and valuenum > 0 then valuenum else null end) as Lactate 
	, avg(case when itemid = 50814 and valuenum > 0 then valuenum else null end) as MetHemoglobin   -- Hemoglobin with F2^(3+)
	, avg(case when itemid = 50815 and valuenum > 0 and valuenum <=70 then valuenum else null end) as O2Flow
	, avg(case when itemid = 50816 and valuenum > 0 and valuenum <= 100 then valuenum else null end) as FiO2   -- Fraction of Inspired Oxygen
	, avg(case when itemid = 50817 and valuenum > 0 and valuenum <= 100 then valuenum else null end) as SO2    -- Oxygen Saturation of Hemoglobin
	, avg(case when itemid = 50818 and valuenum > 0 then valuenum else null end) as pCO2
	, avg(case when itemid = 50819 and valuenum > 0 then valuenum else null end) as PEEP   -- Positive End-Expiratory Pressure of Ventilator
	, avg(case when itemid = 50820 and valuenum > 0 then valuenum else null end) as pH
	, avg(case when itemid = 50821 and valuenum <= 800 then valuenum else null end) as pO2
	, avg(case when itemid = 50822 and valuenum > 0 then valuenum else null end) as Potassium
	, avg(case when itemid = 50823 and valuenum > 0 then valuenum else null end) as RequiredO2
	, avg(case when itemid = 50824 and valuenum > 0 then valuenum else null end) as Sodium
	, avg(case when itemid = 50825 and valuenum > 0 then valuenum else null end) as Temperature
	, avg(case when itemid = 50826 and valuenum > 0 then valuenum else null end) as TidalVolume   -- Air volume of one inhalation or exhalation 
	-- The two itemids below only have value and valuenum is all NULL
	, avg(case when itemid = 50827 and valuenum > 0 then valuenum else null end) as VentilationRate
	, avg(case when itemid = 50828 and valuenum > 0 then valuenum else null end) as Ventilator
from labevents
-- itemid where category = blood gas, fluid = blood from d_labitems
where itemid in (
	50800, 50801, 50802, 50803, 50804, 50805, 50806, 50807, 50808, 50809
  , 50810, 50811, 50812, 50813, 50814, 50815, 50816, 50817, 50818, 50819
  , 50820, 50821, 50822, 50823, 50824, 50825, 50826, 50827, 50828
  , 51545
)
group by hadm_id, charttime 
-- 50800 shows specimen type (arterial or venous blood) and should't be recorded more than twice in a charttime
having count(case when itemid = 50800 then value else null end) < 2; 


-----------------------------------------------------------------
-- Aterial Blood Gas table
-----------------------------------------------------------------
-- This operation is on chartevents table 

drop table if exists mp_bg_art cascade;
create table mp_bg_art as

-----------------------
-- SpO2 table
-----------------------
-- SpO2: Peripheral Oxygen Saturation measured by pulse oximeter

with stg_spo2 as 
(
	select hadm_id, charttime
		, avg(valuenum) as SpO2
	from chartevents
	where itemid in (
		  646     -- CareVue: SpO2 
		, 220277  -- Metavision: O2 saturation pulseoxymetry 
		)
		and valuenum > 0 and valuenum <= 100
		and error is distinct from 1  -- to include NULL
	group by hadm_id, charttime
),

-----------------------
-- FiO2 table
-----------------------
-- FiO2 measured by ventilator, not by blood gas analyser

stg_fio2 as
(
	select hadm_id, charttime
		-- Convert all FiO2 values in percentage
		, max(
			case when itemid = 190 and valuenum > 0.20 and valuenum <= 1 then valuenum * 100 
				when itemid in (3420, 3422) then valuenum
				when itemid = 223835 then
				(case when valuenum >= 0.21 and valuenum <= 1 then valuenum * 100
					-- FiO2 cannot be set to the lower percentage than indoor air (20.9%)
					when valuenum > 1 and valuenum < 21 then null
					when valuenum >= 21 and valuenum <= 100 then valuenum else null end
				) else null end
		) as FiO2_chartevents
	from chartevents
	where itemid in (
		  190     -- Carevue: FiO2 set (in fraction)
		, 3420      -- Carevue: FiO2
		, 3422     -- CareVue: FiO2 (measured)
		, 223835   -- Metavision: Inspired O2 Fraction (FiO2 in %)
		)
		and valuenum > 0 and valuenum < 100
		and error is distinct from 1  -- to include NULL
	group by hadm_id, charttime
),

	
-----------------------
--  Staging table (1)
-----------------------
-- Combine mp_bg, mp_cohort and stg_spo2 tables

stg2 as
(
	select bg.*
		, ceil(extract(epoch from bg.charttime - co.intime)/60.0/60.0)::smallint as hr
		, row_number() over (partition by bg.hadm_id, bg.charttime order by sp.charttime desc) as LatestSpO2
		, sp.SpO2
	from mp_bg bg inner join mp_cohort co
		on bg.hadm_id = co.hadm_id
		and co.excluded = 0
		left join stg_spo2 sp
		on bg.hadm_id = sp.hadm_id
		-- NOTE: mp_bg's charttime (lab) and stg_spo2/stg_fio2's charttime (ICU) have different origins.
		-- We don't know exactly what labevents were for what chartevents. 
		-- 2hr lookback window: when chartevents and labevents occured at different times, 
		-- how much time difference can still represent the same clinical situation?
		and sp.charttime between bg.charttime  - interval '2' hour and bg.charttime
	-- pO2 should have a value for later specimen prediction calculation
	where bg.pO2 is not null
),

-----------------------
--  Staging table (2)
-----------------------
-- Combine st2 and stg_fio2 tables

stg3 as
(
	select bg.*
		-- Many fi.charttime for the same bg.chartime, so the the same bg.charttime should have the same LatestInHour value
		-- If using row_number(), later in main query 'where lastRowFiO2 = 1 and lastRowInHour = 1' can omit some data
		, dense_rank() over (partition by bg.hadm_id, bg.hr order by bg.charttime desc) as LatestInHour
		, row_number() over (partition by bg.hadm_id, bg.charttime order by fi.charttime desc) as LatestFiO2
		, fi.FiO2_chartevents
		
		-- Specimen prediction
		-- Logistic regression: Calculate the arterial specimen prob by linear combination of blood gas values
		, 1 / (1 + exp(-(-0.02544
			+ 0.04598 * pO2
			+ coalesce(-0.15356 * SpO2			   , -0.15356 *   97.49420 +    0.13429)
			+ coalesce( 0.00621 * FiO2_chartevents ,  0.00621 *   51.49550 +   -0.24958)
			+ coalesce( 0.10559 * Hemoglobin       ,  0.10559 *   10.32307 +    0.05954)
			+ coalesce( 0.13251 * SO2              ,  0.13251 *   93.66539 +   -0.23172)
			+ coalesce(-0.01511 * pCO2             , -0.01511 *   42.08866 +   -0.01630)
			+ coalesce( 0.01480 * FIO2             ,  0.01480 *   63.97836 +   -0.31142)
		 	+ coalesce(-0.00200 * AADO2            , -0.00200 *  442.21186 +   -0.01328)
		 	+ coalesce(-0.03220 * Bicarbonate      , -0.03220 *   22.96894 +   -0.06535)
			+ coalesce( 0.05384 * TotalCO2         ,  0.05384 *   24.72632 +   -0.01405)
			+ coalesce( 0.08202 * Lactate          ,  0.08202 *    3.06436 +    0.06038)
			+ coalesce( 0.10956 * pH               ,  0.10956 *    7.36233 +   -0.00617)
			+ coalesce( 0.00848 * O2Flow           ,  0.00848 *    7.59362 +   -0.35803)
		))) as Specimen_prob
	from stg2 bg left join stg_fio2 fi
		on bg.hadm_id = fi.hadm_id
		and fi.charttime between bg.charttime - interval '4' hour and bg.charttime
		-- Filter out null values
		and fi.FIO2_chartevents > 0
	-- Pick the latest chartevent that shares the closest clinical state with labevent
	where bg.LatestSpO2 = 1
)


-----------------------
--  Main query
-----------------------
 
select hadm_id
	, hr
	, charttime
	, Specimen
	, case when Specimen is not null then Specimen
		when Specimen_prob > 0.75 then 'ART' else null end
		as specimen_pred
	, Specimen_prob
	, pO2, SO2, SpO2, pCO2
	, FiO2, FiO2_chartevents
	, AADO2
	
	-- AADO2 = PAO2 (Alveolar) - PaO2 (atery)
	-- Alveolar Gas Equation: PAO2 = FiO2 * (Pb - PH2O) - (PaCO2 / 0.8)
	, case when pO2 is not null 
		and pCO2 is not null 
		and coalesce(FiO2, FiO2_chartevents) is not null
		then (coalesce(FiO2, FiO2_chartevents) / 100) * (760 - 47) - (pCO2 / 0.8) - pO2 else null end
		as AADO2_calc
		
	-- P/F ratio: How much of inspired oxygen actually reaches the arterial blood
	-- 201-300 (mild), 101-200 (moderate), <=100 (severe)
	, case when pO2 is not null and coalesce(FiO2, FiO2_chartevents) is not null
		then pO2 / (coalesce(FiO2, FiO2_chartevents) * 0.01) else null end
		as PaO2FiO2Ratio
	
	, RequiredO2
	, PEEP, O2Flow
	, pH, BaseExcess
	, Bicarbonate, TotalCO2
	, Hematocrit
	, Hemoglobin, CarboxyHemoglobin, MetHemoglobin
	, Chloride, Calcium
	, Sodium, Potassium
	, Lactate
	, Glucose
	, Temperature
	, Intubated, TidalVolume, VentilationRate, Ventilator
from stg3
where LatestInHour = 1 and LatestFiO2 = 1
	and (specimen = 'ART' or specimen_prob > 0.75)
	order by hadm_id, hr;