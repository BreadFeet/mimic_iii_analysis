# MIMIC-III Demo EMR Analysis: In-Hospital Mortality Prediction

## Overview

This project follows an end-to-end clinical data science workflow on the **MIMIC-III Clinical Database Demo** (100 patients), from raw EHR tables to a predictive model of in-hospital mortality. It is built as a learning project, adapting the SQL/Python pipeline from [sukilau/mimiciii-project](https://github.com/sukilau/mimiciii-project) (itself based on [alistairewj/mortality-prediction](https://github.com/alistairewj/mortality-prediction)) to run entirely on a local PostgreSQL instance instead of the original Hive/HQL setup, and rewriting the modeling code in PyTorch instead of Keras.

The two-phase modeling goal follows the original repository:
- **Phase 1**: binary classification — will the patient die during this hospital admission (`hospital_expire_flag`)?
- **Phase 2**: multiclass classification — if they die, roughly when (e.g. <1 day / 1 day–1 week / >1 week)?

Additional proof-of-concept (POC) notebooks explore alternative approaches: an LSTM for the mortality prediction task, and a regressor for predicting time-to-death directly.

## Data

- **Source**: [MIMIC-III Clinical Database Demo v1.4](https://physionet.org/content/mimiciii-demo/1.4/) (100 de-identified ICU patients)
- **Database**: PostgreSQL, built locally using the official [MIT-LCP/mimic-code](https://github.com/MIT-LCP/mimic-code) build scripts (`mimic-iii/buildmimic/postgres/`)
- **UI**: DBeaver, used to browse tables, run and iterate on SQL scripts

## Pipeline

### 1. Cohort and feature extraction (SQL)

Adapted from `Code/SQL/*.sql` in the original repository (Hive `.hql` scripts were skipped — `load_data.hql`/`output_data.hql` are pure CSV load/export steps with no logic, made unnecessary by querying Postgres directly from Python).

Execution order, based on inter-table dependencies:

```
mp_cohort
   ├──> mp_hourly_cohort
   ├──> mp_gcs
   ├──> mp_bg, mp_bg_art
   ├──> mp_lab
   ├──> mp_uo
   └──> mp_vital 
     │
     └──> mp_data 
          = mp_hourly_cohort + mp_vital + mp_gcs + mp_uo + mp_bg_art + mp_lab 
     │
     └──> mp_data_6hr, mp_data_12hr, mp_data_24hr 
          = mp_data + mp_cohort
```

- `mp_cohort`: one row per ICU stay, with exclusion flags (age, missing ICU data, short ICU stay, organ-donor accounts)
- `mp_hourly_cohort`: explodes each ICU stay into one row per hour (from -24h pre-ICU to end of stay) as a join scaffold
- `mp_gcs`,`mp_bg`/`mp_bg_art`, `mp_lab`, `mp_uo`, `mp_vital`: hourly aggregated Glasgow Coma Scale components, arterial blood gases, lab values, urine output, and vitals
- `mp_data`: hourly-level table joining `mp_hourly_cohort` (icustay_id × hr grid) with the hourly vital, GCS, urine output, blood gas, and lab features — one row per (icustay_id, hr), not yet aggregated
- `mp_data_6hr` / `mp_data_12hr` / `mp_data_24hr`: wide feature tables aggregating `mp_data` over the first 6/12/24 hours of each ICU stay (mean/min/max per feature), one row per ICU stay — used as model input

### 2. Modeling (Python)

- **Phase 1 / Phase 2**: `ColumnTransformer` (`OneHotEncoder` for categoricals, `SimpleImputer` for numerics) + `RandomForestClassifier`, tuned with `GridSearchCV`
- **POC_LSTM**: multivariate LSTM (PyTorch) on hourly vitals (0–6h)
- **POC_Regressor**: `RandomForestRegressor` predicting time-to-death directly, as an alternative to multiclass Phase 2

## Key changes from the original repository

- **Hive/HQL → local PostgreSQL**: the whole pipeline runs on a local `mimic` database instead of a Hive cluster
    * `mp_uo.sql`'s sign convention for GU irrigant volumes (itemid 227488/227489) was corrected per [MIT-LCP/mimic-code#204](https://github.com/MIT-LCP/mimic-code/issues/204), which the original script predates
- **Keras → PyTorch**: `POC_LSTM.ipynb`'s `train_lstm`/`predict_lstm` were rewritten using `nn.Module`, manual training loops with `DataLoader`/`TensorDataset`, and explicit `device` handling
- **`LabelBinarizer`/`LabelEncoder` on features → `OneHotEncoder`/`ColumnTransformer`**: the original custom `CustomLabelBinarizer` class (built to handle unseen categories) was replaced with `OneHotEncoder(handle_unknown='ignore')`, which provides the same behavior natively; the `FeatureUnion` + `ItemSelector` structure was refactored into a `ColumnTransformer`
- **All-NaN column handling**: columns that are entirely missing in the (small) demo cohort (e.g. `methemoglobin_*`) are detected and excluded from the training feature list based on the train split only, to avoid `SimpleImputer` failures and train/test leakage
- **Refined time-series data preparation for the LSTM**: the original per-feature approach reshaped each vital sign independently into `[batch, 1, 7]` (timestep=1, feature_dim =7 for 0–6 hr data, treated as static features), which does not use the LSTM's sequential modeling capability. This was restructured into a true multivariate time series of shape `[batch, 7, all_timeseries_features]` (7 timesteps × all vitals as features at each timestep), with a single LSTM trained jointly across all vitals instead of one LSTM per feature, and the data preparation/training code updated accordingly
- **Train/test split discipline**: the last Part of the original notebook where refitting the Random Forest Models with best parameters, not only the refitting process is necessary (as we can use the best estimator from the previous Part), but the preprocessing (e.g. median imputation values, encoding category variables) is done on the entire dataset. In this repo, the preprocessing are done only on the train split and applied unchanged to validation/test splits, to avoid data leakage

## Results and limitations

- **Phase 2 POC**: Random Forest Regressor achieved reasonable validation performance, but showed a large train/validation gap (e.g. high R² on train set vs. negative R² on validation/test set), consistent with overfitting on a very small sample
- The **demo dataset (100 patients)** is the primary limitation throughout: several categorical values and lab items appear in only one of train/validation/test, some engineered features are entirely NaN, and cross-validation folds are small enough that performance estimates are noisy. All findings here should be treated as a pipeline proof-of-concept rather than a clinically meaningful result; re-running against the full MIMIC-III database would be the natural next step

## Settings

To load the dataset into DBeaver,
1. PostgreSQL server download -> DBeaver connection
2. Clone `mimic-code` repository [here](https://github.com/MIT-LCP/mimic-code)
3. Mimic-III demo data (ver 1.4) download (.csv) [here](https://physionet.org/content/mimiciii-demo/1.4/)
4. Follow the code to make database named `mimic`
```
# Bash
# Create database
createdb mimic

# Load table schema
psql -U postgres -W -d mimic -f mimic-iii/buildmimic/postgres/postgres_create_tables.sql

# Load csv data to tables
psql -U postgres -W -d mimic -v mimic_data_dir={path to csv} -f mimic-iii/buildmimic/postgres/postgres_load_data.sql

# Add constrains
psql -U postgres -W -d mimic -f mimic-iii/buildmimic/postgres/postgres_add_constraints.sql

# Add indexes
psql -U postgres -W -d mimic -f mimic-iii/buildmimic/postgres/postgres_add_indexes.sql

# Add comments
psql -U postgres -W -d mimic -f mimic-iii/buildmimic/postgres/postgres_add_comments.sql
```


## References

- sukilau, [mimiciii-project](https://github.com/sukilau/mimiciii-project)
- Johnson, A.E.W. et al., [mortality-prediction](https://github.com/alistairewj/mortality-prediction)
- MIT-LCP, [mimic-code](https://github.com/MIT-LCP/mimic-code)










