-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Extract patients' lab results

drop table if exists mp_lab cascade;
create table mp_lab as

-----------------------
-- Pivot table
-----------------------

with pvt as 
(
	select le.hadm_id
		, ceil(extract(epoch from le.charttime - co.intime)/60.0/60.0)::smallint as hr
		, case when itemid = 50868 then 'ANION GAP'
	        when itemid = 50862 then 'ALBUMIN'
	        when itemid = 51144 then 'BANDS'       -- Band Neutrophils: immature neutrophils
	        when itemid = 50882 then 'BICARBONATE'
	        when itemid = 50885 then 'BILIRUBIN'   -- Breakdown product of Hemoglobin produced in the liver
	        when itemid = 50912 then 'CREATININE'  -- Muscle metabolism waste product cleared by kidneys
	        when itemid = 50902 then 'CHLORIDE'    -- Major blood electrolyte
	        when itemid = 50931 then 'GLUCOSE'
	        when itemid = 51221 then 'HEMATOCRIT'  -- % of Red Blood Cells Volume
	        when itemid = 51222 then 'HEMOGLOBIN'
	        when itemid = 50813 then 'LACTATE'
	        when itemid = 51265 then 'PLATELET'
	        when itemid = 50971 then 'POTASSIUM'
	        when itemid = 51275 then 'PTT'         -- Partial Thromboplastin Time: intrinsic coagulation pathway
	        when itemid = 51237 then 'INR'         -- International Normalised Ratio for PT
	        when itemid = 51274 then 'PT'          -- Prothrombin Time: extrinsic coagulation pathway
	        when itemid = 50983 then 'SODIUM'
	        when itemid = 51006 then 'BUN'         -- Blood Urea Nitrogen 
	        when itemid = 51300 then 'WBC'
	        when itemid = 51301 then 'WBC' else null end as label
	       
	    -- Add in some sanity checks on the values   
		, case when itemid = 50868 and valuenum > 10000 then null -- mEq/L 'ANION GAP'
			when itemid = 50862 and valuenum >    10 then null -- g/dL 'ALBUMIN'
			when itemid = 51144 and valuenum <     0 then null -- %, 'Immature Band Forms'
			when itemid = 51144 and valuenum >   100 then null -- %, 'Immature Band Forms'
			when itemid = 50882 and valuenum > 10000 then null -- mEq/L 'BICARBONATE'
			when itemid = 50885 and valuenum >   150 then null -- mg/dL 'BILIRUBIN'
			when itemid = 50912 and valuenum >   150 then null -- mg/dL 'CREATININE'
			when itemid = 50806 and valuenum > 10000 then null -- mEq/L 'CHLORIDE'
			when itemid = 50902 and valuenum > 10000 then null -- mEq/L 'CHLORIDE'
			when itemid = 50809 and valuenum > 10000 then null -- mg/dL 'GLUCOSE'
			when itemid = 50931 and valuenum > 10000 then null -- mg/dL 'GLUCOSE'
			when itemid = 51221 and valuenum >   100 then null -- % 'HEMATOCRIT'
			-- when itemid = 50810 and valuenum >   100 then null -- % 'HEMATOCRIT'
			when itemid = 51222 and valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
			-- when itemid = 50811 and valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
			when itemid = 50813 and valuenum >    50 then null -- mmol/L 'LACTATE'
			when itemid = 51265 and valuenum > 10000 then null -- K/uL 'PLATELET'
			when itemid = 50971 and valuenum >    30 then null -- mEq/L 'POTASSIUM'
			-- when itemid = 50822 and valuenum >    30 then null -- mEq/L 'POTASSIUM'
			when itemid = 51275 and valuenum >   150 then null -- sec 'PTT'
			when itemid = 51237 and valuenum >    50 then null -- 'INR'
			when itemid = 51274 and valuenum >   150 then null -- sec 'PT'
			when itemid = 50983 and valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
			-- when itemid = 50824 and valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
			when itemid = 51006 and valuenum >   300 then null -- 'BUN'
			when itemid = 51300 and valuenum >  1000 then null -- 'WBC'
			when itemid = 51301 and valuenum >  1000 then null -- 'WBC' 
			else le.valuenum end as valuenum
			
	from labevents le inner join mp_cohort co
		on le.hadm_id = co.hadm_id 
		and co.excluded = 0
	where le.itemid in (
		-- One of the same labels from blood gas category is excluded.
		-- Comment is: LABEL        | CATEGORY   | FLUID | NUMBER OF ROWS IN LABEVENTS
	    50868, -- ANION GAP         | CHEMISTRY  | BLOOD | 2134
	    50862, -- ALBUMIN           | CHEMISTRY  | BLOOD | 414
	    51144, -- BANDS             | HEMATOLOGY | BLOOD | 231
	    50882, -- BICARBONATE       | CHEMISTRY  | BLOOD | 2151
	    50885, -- BILIRUBIN, TOTAL  | CHEMISTRY  | BLOOD | 629
	    50912, -- CREATININE        | CHEMISTRY  | BLOOD | 2175
	    50902, -- CHLORIDE          | CHEMISTRY  | BLOOD | 2160
	    -- 50806, -- CHLORIDE, WHOLE BLOOD | BLOOD GAS | BLOOD | 87
	    50931, -- GLUCOSE           | CHEMISTRY  | BLOOD | 2121
	    -- 50809, -- GLUCOSE        | BLOOD GAS  | BLOOD | 283
	    51221, -- HEMATOCRIT        | HEMATOLOGY | BLOOD | 2317
	    -- 50810, -- HEMATOCRIT, CALCULATED | BLOOD GAS | BLOOD | 126
	    51222, -- HEMOGLOBIN        | HEMATOLOGY | BLOOD | 2024
	    -- 50811, -- HEMOGLOBIN     | BLOOD GAS  | BLOOD | 126
	    50813, -- LACTATE           | BLOOD GAS  | BLOOD | 578
	    51265, -- PLATELET COUNT    | HEMATOLOGY | BLOOD | 2088
	    50971, -- POTASSIUM         | CHEMISTRY  | BLOOD | 2279
	    -- 50822, -- POTASSIUM, WHOLE BLOOD | BLOOD GAS | BLOOD | 256
	    51275, -- PTT               | HEMATOLOGY | BLOOD | 1419
	    51237, -- INR(PT)           | HEMATOLOGY | BLOOD | 1378
	    51274, -- PT                | HEMATOLOGY | BLOOD | 1378
	    50983, -- SODIUM            | CHEMISTRY  | BLOOD | 2185
	    -- 50824, -- SODIUM, WHOLE BLOOD | BLOOD GAS | BLOOD | 107
	    51006, -- UREA NITROGEN     | CHEMISTRY  | BLOOD | 2158
	    51301, -- WHITE BLOOD CELLS | HEMATOLOGY | BLOOD | 2021
	    51300  -- WBC COUNT         | HEMATOLOGY | BLOOD | 1
	)
	and valuenum is not null and valuenum > 0
)

-----------------------
-- Main query
-----------------------

select hadm_id, hr
	-- Pivot label
	, avg(case when label = 'ANION GAP' then valuenum else null end) as ANIONGAP
	, avg(case when label = 'ALBUMIN' then valuenum ELSE null end) as ALBUMIN
    , avg(case when label = 'BANDS' then valuenum ELSE null end) as BANDS
    , avg(case when label = 'BICARBONATE' then valuenum ELSE null end) as BICARBONATE
    , avg(case when label = 'BILIRUBIN' then valuenum ELSE null end) as BILIRUBIN
    , avg(case when label = 'CREATININE' then valuenum ELSE null end) as CREATININE
    , avg(case when label = 'CHLORIDE' then valuenum ELSE null end) as CHLORIDE
    , avg(case when label = 'GLUCOSE' then valuenum ELSE null end) as GLUCOSE
    , avg(case when label = 'HEMATOCRIT' then valuenum ELSE null end) as HEMATOCRIT
    , avg(case when label = 'HEMOGLOBIN' then valuenum ELSE null end) as HEMOGLOBIN
    , avg(case when label = 'LACTATE' then valuenum ELSE null end) as LACTATE
    , avg(case when label = 'PLATELET' then valuenum ELSE null end) as PLATELET
    , avg(case when label = 'POTASSIUM' then valuenum ELSE null end) as POTASSIUM
    , avg(case when label = 'PTT' then valuenum ELSE null end) as PTT
    , avg(case when label = 'INR' then valuenum ELSE null end) as INR
    , avg(case when label = 'PT' then valuenum ELSE null end) as PT
    , avg(case when label = 'SODIUM' then valuenum ELSE null end) as SODIUM
    , avg(case when label = 'BUN' then valuenum ELSE null end) as BUN
    , avg(case when label = 'WBC' then valuenum ELSE null end) as WBC
from pvt
group by hadm_id, hr
order by hadm_id, hr;