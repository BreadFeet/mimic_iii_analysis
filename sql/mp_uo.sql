-- Source: https://github.com/alistairewj/mortality-prediction/tree/master/queries

-----------------------
-- Purpose
-----------------------
-- Extract patients' urine output

drop table if exists mp_uo cascade;
create table mp_uo as

-----------------------
-- Urine output table
-----------------------

with uo as 
(
	select co.icustay_id
		, ceil(extract(epoch from oe.charttime - co.intime)/60.0/60.0)::smallint as hr
		, case when oe.itemid = 227488 and oe.value > 0 then (-1) * oe.value else oe.value end as UrineOutput
	from mp_cohort co inner join outputevents oe
		on co.icustay_id = oe.icustay_id
	where co.excluded = 0
		and oe.iserror is distinct from 1
		and itemid in (
			-- Most frequently occurring urine output observations in CareVue
		    40055, -- Urine Out Foley (catheter)
		    43175, -- Urine
		    40069, -- Urine Out Void (natural, without catheter)
		    40094, -- Urine Out Condom Catheter
		    40715, -- Urine Out Suprapubic Catheter
		    40473, -- Urine Out IleoConduit (through stoma)
		    40085, -- Urine Out Incontinent
		    40086, -- Drain Out #2 Pigtail Catheter (through skin)
		    40057, -- Urine Out Rt Nephrostomy
		    40056, -- Urine Out Lt Nephrostomy
		    40405, -- Urine Out Other
		    40428, -- Urine Out Straight Cather
		    40096, -- Urine Out Ureteral Stent #1 (right)
		    40651, -- Urine Out Ureteral Stent #2 (left)
		    -- Most frequently occurring urine output observations in Metavision
		    226559, -- Foley (catheter)
		    226560, -- Void (without catheter)
		    226561, -- Condom Catheter
		    226584, -- Ileoconduit (through stoma)fcon
		    226563, -- Suprapubic Catheter
		    226564, -- R Nephrostomy
		    226565, -- L Nephrostomy
		    226567, -- Straight Cather
		    226557, -- R Ureteral Stent
		    226558, -- L Ureteral Stent
		    227488, -- GU Irrigant Volume In
		    227489  -- GU Irrigant/Urine Volume Out
	)
)

-----------------------
-- Main query
-----------------------
-- Calculate total urine output per hr after ICU intime

select icustay_id, hr
	, sum(UrineOutput) as UrineOutput
from uo
group by icustay_id, hr
order by icustay_id, hr;