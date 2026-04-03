-- ============================================================
-- Pharma Manufacturing Database EXPANSION to ~300 tables
-- Adds: Clinical Trials, R&D, Regulatory, Pharmacovigilance,
--        Lab/Instruments, Validation, Water/HVAC, Supply Chain,
--        Warehouse, Transport, Costing, HR/Training expansion
-- ============================================================

-- Run: psql -U raghavparnami -d pharma_manufacturing -f scripts/pharma_300_expansion.sql

-- ============================================================
-- SCHEMA: Clinical Trials (~25 tables)
-- ============================================================

CREATE TABLE therapeutic_area (
    area_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE clinical_program (
    program_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    therapeutic_area_id INT REFERENCES therapeutic_area(area_id),
    target_indication VARCHAR(200),
    program_lead_id INT REFERENCES employee(employee_id),
    start_date DATE,
    status VARCHAR(30) DEFAULT 'active'
);

CREATE TABLE clinical_trial (
    trial_id SERIAL PRIMARY KEY,
    trial_number VARCHAR(50) NOT NULL,
    program_id INT REFERENCES clinical_program(program_id),
    product_id INT REFERENCES product(product_id),
    phase VARCHAR(20) NOT NULL,           -- Phase I, II, III, IV
    title VARCHAR(500),
    protocol_number VARCHAR(50),
    start_date DATE,
    end_date DATE,
    status VARCHAR(30) DEFAULT 'planned', -- planned, recruiting, active, completed, terminated
    sponsor VARCHAR(200),
    cro_name VARCHAR(200),
    target_enrollment INT,
    actual_enrollment INT,
    budget NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id)
);

CREATE TABLE trial_site (
    trial_site_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    site_name VARCHAR(200) NOT NULL,
    country_id INT REFERENCES country(country_id),
    principal_investigator VARCHAR(200),
    irb_approval_date DATE,
    status VARCHAR(30) DEFAULT 'active',
    target_patients INT,
    enrolled_patients INT DEFAULT 0
);

CREATE TABLE trial_patient (
    patient_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    trial_site_id INT REFERENCES trial_site(trial_site_id),
    patient_code VARCHAR(30) NOT NULL,
    enrollment_date DATE NOT NULL,
    randomization_group VARCHAR(50),
    status VARCHAR(30) DEFAULT 'active',  -- active, completed, withdrawn, screen_failure
    withdrawal_reason TEXT
);

CREATE TABLE trial_visit (
    visit_id SERIAL PRIMARY KEY,
    patient_id INT REFERENCES trial_patient(patient_id),
    visit_number INT NOT NULL,
    visit_name VARCHAR(100),
    scheduled_date DATE,
    actual_date DATE,
    status VARCHAR(20) DEFAULT 'scheduled'
);

CREATE TABLE trial_adverse_event (
    ae_id SERIAL PRIMARY KEY,
    patient_id INT REFERENCES trial_patient(patient_id),
    trial_id INT REFERENCES clinical_trial(trial_id),
    event_term VARCHAR(200) NOT NULL,
    onset_date DATE,
    resolution_date DATE,
    severity VARCHAR(20),                 -- mild, moderate, severe
    seriousness VARCHAR(20),              -- serious, non-serious
    causality VARCHAR(30),                -- related, possibly_related, unrelated
    outcome VARCHAR(50),
    reported_date DATE,
    meddra_code VARCHAR(20)
);

CREATE TABLE trial_endpoint (
    endpoint_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    endpoint_type VARCHAR(20) NOT NULL,   -- primary, secondary, exploratory
    description TEXT NOT NULL,
    measurement_method VARCHAR(200),
    target_value NUMERIC(12,4),
    actual_value NUMERIC(12,4),
    p_value NUMERIC(8,6),
    met BOOLEAN
);

CREATE TABLE trial_medication (
    medication_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    dosage VARCHAR(50),
    route VARCHAR(50),
    frequency VARCHAR(50),
    quantity_allocated INT,
    quantity_used INT DEFAULT 0
);

CREATE TABLE trial_protocol_amendment (
    amendment_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    amendment_number INT NOT NULL,
    description TEXT NOT NULL,
    reason TEXT,
    approval_date DATE,
    effective_date DATE,
    approved_by INT REFERENCES employee(employee_id)
);

CREATE TABLE trial_monitoring_visit (
    monitoring_id SERIAL PRIMARY KEY,
    trial_site_id INT REFERENCES trial_site(trial_site_id),
    monitor_name VARCHAR(100),
    visit_date DATE NOT NULL,
    visit_type VARCHAR(30),               -- initiation, interim, close_out
    findings TEXT,
    action_items TEXT,
    status VARCHAR(20) DEFAULT 'completed'
);

CREATE TABLE trial_budget_line (
    budget_line_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    category VARCHAR(50) NOT NULL,        -- cro_fees, lab_costs, drug_supply, site_payments
    planned_amount NUMERIC(14,2),
    actual_amount NUMERIC(14,2) DEFAULT 0,
    currency_id INT REFERENCES currency(currency_id)
);

CREATE TABLE investigational_product (
    ip_id SERIAL PRIMARY KEY,
    trial_id INT REFERENCES clinical_trial(trial_id),
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    quantity_manufactured INT,
    quantity_shipped INT DEFAULT 0,
    quantity_returned INT DEFAULT 0,
    expiry_date DATE,
    storage_condition_id INT REFERENCES storage_condition(condition_id)
);

-- ============================================================
-- SCHEMA: R&D / Formulation Development (~20 tables)
-- ============================================================

CREATE TABLE research_project (
    project_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    project_code VARCHAR(30),
    therapeutic_area_id INT REFERENCES therapeutic_area(area_id),
    project_lead_id INT REFERENCES employee(employee_id),
    start_date DATE,
    target_completion_date DATE,
    status VARCHAR(30) DEFAULT 'active',
    budget NUMERIC(14,2),
    description TEXT
);

CREATE TABLE formulation (
    formulation_id SERIAL PRIMARY KEY,
    project_id INT REFERENCES research_project(project_id),
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    formulation_code VARCHAR(30),
    dosage_form_id INT REFERENCES dosage_form(dosage_form_id),
    target_strength VARCHAR(50),
    status VARCHAR(30) DEFAULT 'development',
    created_date DATE,
    approved_date DATE
);

CREATE TABLE formulation_ingredient (
    ingredient_id SERIAL PRIMARY KEY,
    formulation_id INT REFERENCES formulation(formulation_id),
    material_id INT REFERENCES raw_material(material_id),
    quantity_per_unit NUMERIC(12,4),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    function VARCHAR(50),                 -- active, binder, filler, disintegrant, lubricant
    is_critical BOOLEAN DEFAULT FALSE
);

CREATE TABLE lab_experiment (
    experiment_id SERIAL PRIMARY KEY,
    project_id INT REFERENCES research_project(project_id),
    formulation_id INT REFERENCES formulation(formulation_id),
    experiment_code VARCHAR(30),
    objective TEXT,
    method TEXT,
    start_date DATE,
    end_date DATE,
    performed_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE experiment_result (
    result_id SERIAL PRIMARY KEY,
    experiment_id INT REFERENCES lab_experiment(experiment_id),
    parameter_name VARCHAR(100) NOT NULL,
    result_value NUMERIC(12,4),
    result_text VARCHAR(500),
    unit VARCHAR(30),
    within_target BOOLEAN,
    notes TEXT
);

CREATE TABLE scale_up_batch (
    scale_up_id SERIAL PRIMARY KEY,
    formulation_id INT REFERENCES formulation(formulation_id),
    batch_number VARCHAR(30),
    scale VARCHAR(20),                    -- lab, pilot, exhibit, commercial
    batch_size NUMERIC(12,2),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    start_date DATE,
    end_date DATE,
    yield_pct NUMERIC(5,2),
    status VARCHAR(20) DEFAULT 'planned',
    performed_by INT REFERENCES employee(employee_id),
    site_id INT REFERENCES site(site_id)
);

CREATE TABLE dissolution_profile (
    profile_id SERIAL PRIMARY KEY,
    scale_up_id INT REFERENCES scale_up_batch(scale_up_id),
    batch_id INT REFERENCES batch(batch_id),
    medium VARCHAR(100),
    rpm INT,
    time_point_min INT NOT NULL,
    dissolution_pct NUMERIC(5,2),
    test_date DATE,
    tested_by INT REFERENCES employee(employee_id)
);

CREATE TABLE reference_standard (
    standard_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    lot_number VARCHAR(50),
    potency_pct NUMERIC(6,2),
    expiry_date DATE,
    storage_condition_id INT REFERENCES storage_condition(condition_id),
    certificate_path VARCHAR(255),
    material_id INT REFERENCES raw_material(material_id)
);

CREATE TABLE analytical_method (
    method_id SERIAL PRIMARY KEY,
    method_code VARCHAR(30) NOT NULL,
    name VARCHAR(200) NOT NULL,
    method_type VARCHAR(50),              -- HPLC, GC, titration, spectroscopy, dissolution
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    status VARCHAR(20) DEFAULT 'current',
    effective_date DATE,
    author_id INT REFERENCES employee(employee_id)
);

CREATE TABLE method_validation (
    validation_id SERIAL PRIMARY KEY,
    method_id INT REFERENCES analytical_method(method_id),
    validation_type VARCHAR(50),          -- full, partial, transfer
    protocol_number VARCHAR(50),
    start_date DATE,
    completion_date DATE,
    status VARCHAR(20) DEFAULT 'in_progress',
    approved_by INT REFERENCES employee(employee_id)
);

CREATE TABLE method_validation_result (
    result_id SERIAL PRIMARY KEY,
    validation_id INT REFERENCES method_validation(validation_id),
    parameter VARCHAR(50) NOT NULL,       -- accuracy, precision, linearity, specificity, LOD, LOQ
    acceptance_criteria VARCHAR(200),
    result_value VARCHAR(200),
    passed BOOLEAN NOT NULL
);

-- ============================================================
-- SCHEMA: Regulatory Affairs (~20 tables)
-- ============================================================

CREATE TABLE regulatory_submission (
    submission_id SERIAL PRIMARY KEY,
    submission_number VARCHAR(50) NOT NULL,
    product_id INT REFERENCES product(product_id),
    body_id INT REFERENCES regulatory_body(body_id),
    submission_type VARCHAR(50),           -- NDA, ANDA, MAA, variation, renewal
    submission_date DATE,
    target_approval_date DATE,
    actual_approval_date DATE,
    status VARCHAR(30) DEFAULT 'preparation',
    lead_id INT REFERENCES employee(employee_id)
);

CREATE TABLE submission_section (
    section_id SERIAL PRIMARY KEY,
    submission_id INT REFERENCES regulatory_submission(submission_id),
    section_number VARCHAR(20),           -- 3.2.S, 3.2.P, CTD Module 1-5
    title VARCHAR(200) NOT NULL,
    owner_id INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'draft',
    due_date DATE,
    completed_date DATE
);

CREATE TABLE regulatory_query (
    query_id SERIAL PRIMARY KEY,
    submission_id INT REFERENCES regulatory_submission(submission_id),
    query_number VARCHAR(30),
    received_date DATE NOT NULL,
    due_date DATE,
    question TEXT NOT NULL,
    response TEXT,
    responded_date DATE,
    status VARCHAR(20) DEFAULT 'open',
    assigned_to INT REFERENCES employee(employee_id)
);

CREATE TABLE regulatory_commitment (
    commitment_id SERIAL PRIMARY KEY,
    submission_id INT REFERENCES regulatory_submission(submission_id),
    commitment_text TEXT NOT NULL,
    due_date DATE,
    status VARCHAR(20) DEFAULT 'open',
    owner_id INT REFERENCES employee(employee_id),
    completed_date DATE
);

CREATE TABLE regulatory_inspection (
    inspection_id SERIAL PRIMARY KEY,
    body_id INT REFERENCES regulatory_body(body_id),
    site_id INT REFERENCES site(site_id),
    inspection_type VARCHAR(50),          -- pre_approval, routine, for_cause
    start_date DATE NOT NULL,
    end_date DATE,
    lead_inspector VARCHAR(100),
    classification VARCHAR(30),           -- NAI, VAI, OAI (FDA); compliant, non-compliant
    observations_count INT DEFAULT 0,
    form483_issued BOOLEAN DEFAULT FALSE
);

CREATE TABLE inspection_observation (
    observation_id SERIAL PRIMARY KEY,
    inspection_id INT REFERENCES regulatory_inspection(inspection_id),
    observation_number INT,
    category VARCHAR(50),
    description TEXT NOT NULL,
    capa_id INT REFERENCES capa(capa_id),
    response TEXT,
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE drug_master_file (
    dmf_id SERIAL PRIMARY KEY,
    dmf_number VARCHAR(30) NOT NULL,
    dmf_type VARCHAR(20),                 -- Type II (Drug Substance), Type III (Packaging)
    holder_name VARCHAR(200),
    material_id INT REFERENCES raw_material(material_id),
    filing_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    country_id INT REFERENCES country(country_id)
);

CREATE TABLE labeling (
    labeling_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    label_type VARCHAR(50),               -- primary, secondary, patient_insert, prescribing_info
    version INT DEFAULT 1,
    effective_date DATE,
    status VARCHAR(20) DEFAULT 'current',
    approved_by INT REFERENCES employee(employee_id),
    content_hash VARCHAR(64)
);

-- ============================================================
-- SCHEMA: Pharmacovigilance (~15 tables)
-- ============================================================

CREATE TABLE adverse_event_report (
    report_id SERIAL PRIMARY KEY,
    report_number VARCHAR(30) NOT NULL,
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    report_date DATE NOT NULL,
    report_source VARCHAR(50),            -- spontaneous, clinical_trial, literature, patient
    reporter_type VARCHAR(50),            -- physician, pharmacist, patient, consumer
    country_id INT REFERENCES country(country_id),
    seriousness VARCHAR(20),              -- serious, non_serious
    event_description TEXT NOT NULL,
    meddra_pt VARCHAR(200),
    meddra_soc VARCHAR(200),
    outcome VARCHAR(50),                  -- recovered, recovering, not_recovered, fatal, unknown
    causality_assessment VARCHAR(30),
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE ae_report_medication (
    id SERIAL PRIMARY KEY,
    report_id INT REFERENCES adverse_event_report(report_id),
    product_id INT REFERENCES product(product_id),
    batch_number VARCHAR(30),
    dose VARCHAR(50),
    route VARCHAR(50),
    start_date DATE,
    end_date DATE,
    indication VARCHAR(200),
    drug_role VARCHAR(20)                 -- suspect, concomitant, interacting
);

CREATE TABLE signal_detection (
    signal_id SERIAL PRIMARY KEY,
    signal_number VARCHAR(30),
    product_id INT REFERENCES product(product_id),
    event_term VARCHAR(200) NOT NULL,
    detection_date DATE NOT NULL,
    detection_method VARCHAR(50),         -- PRR, ROR, BCPNN, EBGM
    score NUMERIC(8,4),
    status VARCHAR(30) DEFAULT 'under_evaluation',
    assigned_to INT REFERENCES employee(employee_id),
    conclusion TEXT
);

CREATE TABLE periodic_safety_report (
    psr_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    report_type VARCHAR(30),              -- PSUR, PBRER, DSUR
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    submission_date DATE,
    body_id INT REFERENCES regulatory_body(body_id),
    status VARCHAR(20) DEFAULT 'preparation',
    author_id INT REFERENCES employee(employee_id)
);

CREATE TABLE risk_management_plan (
    rmp_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    effective_date DATE,
    identified_risks TEXT,
    potential_risks TEXT,
    missing_information TEXT,
    risk_minimization_measures TEXT,
    status VARCHAR(20) DEFAULT 'current'
);

-- ============================================================
-- SCHEMA: Lab Instruments & Qualification (~15 tables)
-- ============================================================

CREATE TABLE instrument_category (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE lab_instrument (
    instrument_id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(200) NOT NULL,
    category_id INT REFERENCES instrument_category(category_id),
    manufacturer VARCHAR(100),
    model VARCHAR(50),
    serial_number VARCHAR(50),
    location_area_id INT REFERENCES production_area(area_id),
    install_date DATE,
    status VARCHAR(20) DEFAULT 'qualified',
    last_qualification_date DATE
);

CREATE TABLE instrument_qualification (
    qual_id SERIAL PRIMARY KEY,
    instrument_id INT REFERENCES lab_instrument(instrument_id),
    qual_type VARCHAR(30) NOT NULL,       -- IQ, OQ, PQ, requalification
    protocol_number VARCHAR(50),
    start_date DATE,
    completion_date DATE,
    performed_by INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'in_progress',
    passed BOOLEAN
);

CREATE TABLE instrument_usage_log (
    log_id SERIAL PRIMARY KEY,
    instrument_id INT REFERENCES lab_instrument(instrument_id),
    used_by INT REFERENCES employee(employee_id),
    usage_date TIMESTAMP NOT NULL,
    sample_id INT REFERENCES qc_sample(sample_id),
    purpose VARCHAR(200),
    run_number VARCHAR(30)
);

CREATE TABLE reagent (
    reagent_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    grade VARCHAR(50),                    -- AR, HPLC, ACS
    cas_number VARCHAR(30),
    supplier_id INT REFERENCES supplier(supplier_id),
    lot_number VARCHAR(50),
    received_date DATE,
    expiry_date DATE,
    opened_date DATE,
    status VARCHAR(20) DEFAULT 'available',
    storage_condition_id INT REFERENCES storage_condition(condition_id)
);

CREATE TABLE column_inventory (
    column_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    column_type VARCHAR(50),              -- C18, C8, HILIC, ion_exchange
    dimensions VARCHAR(50),
    particle_size VARCHAR(20),
    manufacturer VARCHAR(100),
    lot_number VARCHAR(50),
    install_date DATE,
    usage_count INT DEFAULT 0,
    max_usage INT DEFAULT 2000,
    instrument_id INT REFERENCES lab_instrument(instrument_id),
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE system_suitability (
    sst_id SERIAL PRIMARY KEY,
    instrument_id INT REFERENCES lab_instrument(instrument_id),
    column_id INT REFERENCES column_inventory(column_id),
    test_date TIMESTAMP NOT NULL,
    theoretical_plates INT,
    tailing_factor NUMERIC(5,3),
    resolution NUMERIC(5,3),
    rsd_area_pct NUMERIC(5,3),
    passed BOOLEAN NOT NULL,
    performed_by INT REFERENCES employee(employee_id),
    method_id INT REFERENCES analytical_method(method_id)
);

-- ============================================================
-- SCHEMA: Validation (~15 tables)
-- ============================================================

CREATE TABLE validation_type (
    val_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,           -- Process, Cleaning, Computer, Method, Transport
    description TEXT
);

CREATE TABLE validation_protocol (
    protocol_id SERIAL PRIMARY KEY,
    protocol_number VARCHAR(50) NOT NULL,
    val_type_id INT REFERENCES validation_type(val_type_id),
    product_id INT REFERENCES product(product_id),
    equipment_id INT REFERENCES equipment(equipment_id),
    title VARCHAR(300),
    author_id INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id),
    effective_date DATE,
    status VARCHAR(20) DEFAULT 'draft',
    version INT DEFAULT 1
);

CREATE TABLE validation_run (
    run_id SERIAL PRIMARY KEY,
    protocol_id INT REFERENCES validation_protocol(protocol_id),
    run_number INT NOT NULL,
    batch_id INT REFERENCES batch(batch_id),
    start_date DATE,
    end_date DATE,
    performed_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE validation_test_result (
    result_id SERIAL PRIMARY KEY,
    run_id INT REFERENCES validation_run(run_id),
    test_name VARCHAR(200) NOT NULL,
    acceptance_criteria VARCHAR(200),
    actual_result VARCHAR(200),
    passed BOOLEAN NOT NULL,
    notes TEXT
);

CREATE TABLE cleaning_validation (
    cv_id SERIAL PRIMARY KEY,
    protocol_id INT REFERENCES validation_protocol(protocol_id),
    equipment_id INT REFERENCES equipment(equipment_id),
    product_before_id INT REFERENCES product(product_id),
    product_after_id INT REFERENCES product(product_id),
    swab_limit_mcg_per_sqcm NUMERIC(10,4),
    rinse_limit_ppm NUMERIC(10,4),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE cleaning_validation_result (
    result_id SERIAL PRIMARY KEY,
    cv_id INT REFERENCES cleaning_validation(cv_id),
    sample_type VARCHAR(20),              -- swab, rinse, visual
    sample_location VARCHAR(100),
    residue_found NUMERIC(10,4),
    limit_value NUMERIC(10,4),
    passed BOOLEAN NOT NULL,
    tested_by INT REFERENCES employee(employee_id),
    test_date DATE
);

CREATE TABLE computer_system_validation (
    csv_id SERIAL PRIMARY KEY,
    system_name VARCHAR(200) NOT NULL,
    system_category VARCHAR(20),          -- GAMP 3, 4, 5
    vendor VARCHAR(200),
    val_type_id INT REFERENCES validation_type(val_type_id),
    protocol_number VARCHAR(50),
    validation_date DATE,
    next_review_date DATE,
    status VARCHAR(20) DEFAULT 'validated',
    owner_id INT REFERENCES employee(employee_id)
);

-- ============================================================
-- SCHEMA: Water & HVAC Systems (~15 tables)
-- ============================================================

CREATE TABLE water_system (
    system_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,           -- PW, WFI, Pure Steam
    system_type VARCHAR(50),
    site_id INT REFERENCES site(site_id),
    capacity_lph NUMERIC(10,2),
    generation_method VARCHAR(100),
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE water_sampling_point (
    point_id SERIAL PRIMARY KEY,
    system_id INT REFERENCES water_system(system_id),
    point_name VARCHAR(100) NOT NULL,
    location VARCHAR(200),
    point_type VARCHAR(30),               -- use_point, return, generation, storage
    sampling_frequency VARCHAR(30)
);

CREATE TABLE water_test_result (
    test_id SERIAL PRIMARY KEY,
    point_id INT REFERENCES water_sampling_point(point_id),
    test_date TIMESTAMP NOT NULL,
    toc_ppb NUMERIC(8,2),
    conductivity_us NUMERIC(8,2),
    endotoxin_eu_ml NUMERIC(8,4),
    microbial_cfu_ml NUMERIC(8,2),
    ph NUMERIC(4,2),
    passed BOOLEAN NOT NULL,
    tested_by INT REFERENCES employee(employee_id),
    alert_triggered BOOLEAN DEFAULT FALSE,
    action_triggered BOOLEAN DEFAULT FALSE
);

CREATE TABLE water_alert_action_level (
    level_id SERIAL PRIMARY KEY,
    system_id INT REFERENCES water_system(system_id),
    parameter VARCHAR(50),
    alert_limit NUMERIC(10,4),
    action_limit NUMERIC(10,4),
    spec_limit NUMERIC(10,4),
    uom VARCHAR(20)
);

CREATE TABLE hvac_system (
    hvac_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    system_type VARCHAR(50),              -- AHU, chiller, boiler, cooling_tower
    area_id INT REFERENCES production_area(area_id),
    site_id INT REFERENCES site(site_id),
    capacity VARCHAR(50),
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE hvac_monitoring (
    monitoring_id SERIAL PRIMARY KEY,
    hvac_id INT REFERENCES hvac_system(hvac_id),
    reading_time TIMESTAMP NOT NULL,
    supply_temp_c NUMERIC(5,1),
    return_temp_c NUMERIC(5,1),
    humidity_pct NUMERIC(5,1),
    differential_pressure_pa NUMERIC(6,2),
    filter_dp_pa NUMERIC(6,2),
    within_spec BOOLEAN NOT NULL
);

CREATE TABLE hvac_filter (
    filter_id SERIAL PRIMARY KEY,
    hvac_id INT REFERENCES hvac_system(hvac_id),
    filter_type VARCHAR(50),              -- pre_filter, HEPA, carbon
    location VARCHAR(100),
    install_date DATE,
    replacement_due_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    efficiency_pct NUMERIC(5,2)
);

CREATE TABLE hvac_maintenance (
    maintenance_id SERIAL PRIMARY KEY,
    hvac_id INT REFERENCES hvac_system(hvac_id),
    maintenance_type VARCHAR(50),
    scheduled_date DATE,
    completed_date DATE,
    performed_by INT REFERENCES employee(employee_id),
    findings TEXT,
    cost NUMERIC(12,2),
    status VARCHAR(20) DEFAULT 'scheduled'
);

-- ============================================================
-- SCHEMA: Supply Chain Planning (~15 tables)
-- ============================================================

CREATE TABLE demand_forecast (
    forecast_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    site_id INT REFERENCES site(site_id),
    forecast_month DATE NOT NULL,
    forecast_quantity INT NOT NULL,
    actual_quantity INT,
    accuracy_pct NUMERIC(5,2),
    created_by INT REFERENCES employee(employee_id),
    created_date DATE
);

CREATE TABLE production_plan (
    plan_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    plan_month DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'draft',
    approved_by INT REFERENCES employee(employee_id),
    approved_date DATE
);

CREATE TABLE production_plan_line (
    plan_line_id SERIAL PRIMARY KEY,
    plan_id INT REFERENCES production_plan(plan_id),
    product_id INT REFERENCES product(product_id),
    line_id INT REFERENCES production_line(line_id),
    planned_batches INT,
    planned_quantity NUMERIC(14,2),
    week_number INT
);

CREATE TABLE material_requirement (
    requirement_id SERIAL PRIMARY KEY,
    plan_id INT REFERENCES production_plan(plan_id),
    material_id INT REFERENCES raw_material(material_id),
    required_quantity NUMERIC(14,2),
    available_quantity NUMERIC(14,2),
    shortage_quantity NUMERIC(14,2),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    required_date DATE
);

CREATE TABLE inventory_snapshot (
    snapshot_id SERIAL PRIMARY KEY,
    material_id INT REFERENCES raw_material(material_id),
    product_id INT REFERENCES product(product_id),
    site_id INT REFERENCES site(site_id),
    snapshot_date DATE NOT NULL,
    quantity_on_hand NUMERIC(14,2),
    quantity_allocated NUMERIC(14,2),
    quantity_available NUMERIC(14,2),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    value NUMERIC(14,2)
);

CREATE TABLE warehouse_zone (
    zone_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    name VARCHAR(100) NOT NULL,
    zone_type VARCHAR(50),                -- ambient, cold, frozen, quarantine, hazardous
    condition_id INT REFERENCES storage_condition(condition_id),
    capacity_pallets INT
);

CREATE TABLE warehouse_location (
    location_id SERIAL PRIMARY KEY,
    zone_id INT REFERENCES warehouse_zone(zone_id),
    location_code VARCHAR(30) NOT NULL,
    rack VARCHAR(10),
    level VARCHAR(10),
    position VARCHAR(10),
    is_occupied BOOLEAN DEFAULT FALSE,
    current_material_lot_id INT REFERENCES material_lot(lot_id)
);

CREATE TABLE warehouse_movement (
    movement_id SERIAL PRIMARY KEY,
    from_location_id INT REFERENCES warehouse_location(location_id),
    to_location_id INT REFERENCES warehouse_location(location_id),
    lot_id INT REFERENCES material_lot(lot_id),
    quantity NUMERIC(12,2),
    movement_type VARCHAR(30),            -- receipt, putaway, pick, transfer, dispatch
    movement_date TIMESTAMP DEFAULT NOW(),
    performed_by INT REFERENCES employee(employee_id),
    reference_doc VARCHAR(50)
);

CREATE TABLE transport_order (
    transport_id SERIAL PRIMARY KEY,
    shipment_id INT REFERENCES shipment(shipment_id),
    carrier VARCHAR(100),
    vehicle_number VARCHAR(30),
    driver_name VARCHAR(100),
    departure_time TIMESTAMP,
    arrival_time TIMESTAMP,
    temperature_monitored BOOLEAN DEFAULT FALSE,
    min_temp_recorded NUMERIC(5,1),
    max_temp_recorded NUMERIC(5,1),
    condition_id INT REFERENCES storage_condition(condition_id),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE transport_temperature_log (
    log_id SERIAL PRIMARY KEY,
    transport_id INT REFERENCES transport_order(transport_id),
    reading_time TIMESTAMP NOT NULL,
    temperature_c NUMERIC(5,1) NOT NULL,
    humidity_pct NUMERIC(5,1),
    within_spec BOOLEAN NOT NULL
);

-- ============================================================
-- SCHEMA: Costing & Finance (~10 tables)
-- ============================================================

CREATE TABLE cost_allocation (
    allocation_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    cost_center_id INT REFERENCES cost_center(cost_center_id),
    cost_type VARCHAR(50),
    amount NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id),
    period DATE,
    allocated_date DATE DEFAULT CURRENT_DATE
);

CREATE TABLE product_costing (
    costing_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    effective_date DATE,
    material_cost_per_unit NUMERIC(10,4),
    labor_cost_per_unit NUMERIC(10,4),
    overhead_cost_per_unit NUMERIC(10,4),
    total_cost_per_unit NUMERIC(10,4),
    selling_price_per_unit NUMERIC(10,4),
    margin_pct NUMERIC(5,2),
    currency_id INT REFERENCES currency(currency_id)
);

CREATE TABLE budget (
    budget_id SERIAL PRIMARY KEY,
    department_id INT REFERENCES department(department_id),
    fiscal_year INT NOT NULL,
    budget_category VARCHAR(50),
    planned_amount NUMERIC(14,2),
    actual_amount NUMERIC(14,2) DEFAULT 0,
    variance NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id)
);

CREATE TABLE invoice (
    invoice_id SERIAL PRIMARY KEY,
    invoice_number VARCHAR(30) NOT NULL,
    supplier_id INT REFERENCES supplier(supplier_id),
    customer_id INT REFERENCES customer(customer_id),
    invoice_type VARCHAR(20),             -- purchase, sales
    invoice_date DATE NOT NULL,
    due_date DATE,
    total_amount NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id),
    status VARCHAR(20) DEFAULT 'open',
    po_id INT REFERENCES purchase_order(po_id),
    so_id INT REFERENCES sales_order(order_id)
);

CREATE TABLE invoice_line (
    line_id SERIAL PRIMARY KEY,
    invoice_id INT REFERENCES invoice(invoice_id),
    description VARCHAR(200),
    quantity NUMERIC(12,2),
    unit_price NUMERIC(12,4),
    line_total NUMERIC(14,2),
    product_id INT REFERENCES product(product_id),
    material_id INT REFERENCES raw_material(material_id)
);

-- ============================================================
-- SCHEMA: HR / Training Expansion (~15 tables)
-- ============================================================

CREATE TABLE job_role (
    role_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    department_id INT REFERENCES department(department_id),
    grade VARCHAR(20),
    min_salary NUMERIC(12,2),
    max_salary NUMERIC(12,2),
    description TEXT
);

CREATE TABLE employee_role_history (
    history_id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employee(employee_id),
    role_id INT REFERENCES job_role(role_id),
    start_date DATE NOT NULL,
    end_date DATE,
    reason VARCHAR(100)
);

CREATE TABLE training_curriculum (
    curriculum_id SERIAL PRIMARY KEY,
    role_id INT REFERENCES job_role(role_id),
    training_type_id INT REFERENCES training_type(training_type_id),
    is_mandatory BOOLEAN DEFAULT TRUE,
    frequency_months INT
);

CREATE TABLE training_session (
    session_id SERIAL PRIMARY KEY,
    training_type_id INT REFERENCES training_type(training_type_id),
    session_date DATE NOT NULL,
    trainer_id INT REFERENCES employee(employee_id),
    location VARCHAR(100),
    duration_hours NUMERIC(4,1),
    max_attendees INT,
    status VARCHAR(20) DEFAULT 'scheduled'
);

CREATE TABLE training_attendance (
    attendance_id SERIAL PRIMARY KEY,
    session_id INT REFERENCES training_session(session_id),
    employee_id INT REFERENCES employee(employee_id),
    attended BOOLEAN DEFAULT FALSE,
    score NUMERIC(5,2),
    passed BOOLEAN,
    certificate_issued BOOLEAN DEFAULT FALSE
);

CREATE TABLE employee_competency (
    competency_id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employee(employee_id),
    competency_name VARCHAR(100) NOT NULL,
    level VARCHAR(20),                    -- basic, intermediate, advanced, expert
    assessed_date DATE,
    assessed_by INT REFERENCES employee(employee_id),
    next_assessment_date DATE
);

CREATE TABLE incident_report (
    incident_id SERIAL PRIMARY KEY,
    incident_number VARCHAR(30) NOT NULL,
    incident_date TIMESTAMP NOT NULL,
    reported_by INT REFERENCES employee(employee_id),
    area_id INT REFERENCES production_area(area_id),
    incident_type VARCHAR(50),            -- safety, spill, injury, near_miss, fire
    severity VARCHAR(20),
    description TEXT NOT NULL,
    immediate_action TEXT,
    root_cause TEXT,
    capa_id INT REFERENCES capa(capa_id),
    status VARCHAR(20) DEFAULT 'open',
    lost_time_hours NUMERIC(6,1) DEFAULT 0
);

CREATE TABLE safety_inspection (
    inspection_id SERIAL PRIMARY KEY,
    area_id INT REFERENCES production_area(area_id),
    inspection_date DATE NOT NULL,
    inspector_id INT REFERENCES employee(employee_id),
    checklist_version VARCHAR(20),
    items_checked INT,
    items_passed INT,
    findings TEXT,
    status VARCHAR(20) DEFAULT 'completed'
);

CREATE TABLE ppe_inventory (
    ppe_id SERIAL PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    item_type VARCHAR(50),                -- gloves, goggles, mask, gown, shoe_cover
    site_id INT REFERENCES site(site_id),
    current_stock INT,
    reorder_point INT,
    unit_cost NUMERIC(8,2),
    supplier_id INT REFERENCES supplier(supplier_id)
);

CREATE TABLE ppe_issuance (
    issuance_id SERIAL PRIMARY KEY,
    ppe_id INT REFERENCES ppe_inventory(ppe_id),
    employee_id INT REFERENCES employee(employee_id),
    issue_date DATE NOT NULL,
    quantity INT NOT NULL,
    area_id INT REFERENCES production_area(area_id)
);

-- ============================================================
-- SCHEMA: Vendor Qualification (~10 tables)
-- ============================================================

CREATE TABLE vendor_qualification (
    qual_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    material_id INT REFERENCES raw_material(material_id),
    qualification_type VARCHAR(50),       -- initial, requalification, change
    start_date DATE,
    completion_date DATE,
    status VARCHAR(20) DEFAULT 'in_progress',
    approved_by INT REFERENCES employee(employee_id)
);

CREATE TABLE vendor_qualification_test (
    test_id SERIAL PRIMARY KEY,
    qual_id INT REFERENCES vendor_qualification(qual_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    test_date DATE,
    result VARCHAR(200),
    passed BOOLEAN NOT NULL,
    tested_by INT REFERENCES employee(employee_id)
);

CREATE TABLE vendor_agreement (
    agreement_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    agreement_type VARCHAR(50),           -- quality, supply, confidentiality, service_level
    effective_date DATE,
    expiry_date DATE,
    auto_renew BOOLEAN DEFAULT FALSE,
    status VARCHAR(20) DEFAULT 'active',
    document_id INT REFERENCES document(document_id)
);

CREATE TABLE vendor_scorecard (
    scorecard_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    quality_score NUMERIC(5,2),
    delivery_score NUMERIC(5,2),
    price_score NUMERIC(5,2),
    service_score NUMERIC(5,2),
    overall_score NUMERIC(5,2),
    lots_received INT,
    lots_rejected INT,
    on_time_delivery_pct NUMERIC(5,2)
);

CREATE TABLE vendor_corrective_action (
    vca_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    issue_date DATE NOT NULL,
    issue_description TEXT NOT NULL,
    root_cause TEXT,
    corrective_action TEXT,
    due_date DATE,
    completion_date DATE,
    status VARCHAR(20) DEFAULT 'open',
    verified_by INT REFERENCES employee(employee_id)
);

-- ============================================================
-- SAMPLE DATA for new tables
-- ============================================================

-- Therapeutic Areas
INSERT INTO therapeutic_area (name, description) VALUES
('Cardiology', 'Heart and cardiovascular diseases'),
('Neurology', 'Brain and nervous system disorders'),
('Oncology', 'Cancer treatment'),
('Infectious Disease', 'Bacterial and viral infections'),
('Metabolic', 'Diabetes and metabolic disorders');

-- Research Projects
INSERT INTO research_project (name, project_code, therapeutic_area_id, project_lead_id, start_date, status, budget) VALUES
('Next-Gen Paracetamol ER', 'PRJ-001', 1, 1, '2024-01-01', 'active', 500000.00),
('Metformin XR 1500mg', 'PRJ-002', 5, 5, '2024-06-01', 'active', 750000.00),
('Atorvastatin Combo Tablet', 'PRJ-003', 1, 1, '2025-01-01', 'planning', 1000000.00);

-- Clinical Trials
INSERT INTO clinical_trial (trial_number, program_id, product_id, phase, title, start_date, status, target_enrollment, budget, currency_id) VALUES
('CT-2024-001', NULL, 1, 'Phase IV', 'Post-marketing surveillance of Paracetamol 500mg', '2024-06-01', 'active', 500, 200000.00, 1),
('CT-2025-001', NULL, 3, 'Phase III', 'Efficacy of Metformin 500mg vs placebo', '2025-01-01', 'recruiting', 1000, 2000000.00, 1);

-- Regulatory Submissions
INSERT INTO regulatory_submission (submission_number, product_id, body_id, submission_type, submission_date, status, lead_id) VALUES
('NDA-2024-001', 1, 1, 'variation', '2024-03-15', 'approved', 7),
('ANDA-2025-001', 8, 1, 'ANDA', '2025-02-01', 'under_review', 7),
('MAA-2025-001', 3, 2, 'variation', '2025-03-01', 'preparation', 13);

-- Validation Types
INSERT INTO validation_type (name, description) VALUES
('Process Validation', 'Validation of manufacturing processes'),
('Cleaning Validation', 'Validation of equipment cleaning procedures'),
('Computer System Validation', 'Validation of computerized systems'),
('Method Validation', 'Validation of analytical methods'),
('Transport Validation', 'Validation of transport conditions');

-- Water Systems
INSERT INTO water_system (name, system_type, site_id, capacity_lph, generation_method, status) VALUES
('PW System US', 'Purified Water', 1, 5000, 'RO + EDI', 'active'),
('WFI System US', 'Water for Injection', 1, 2000, 'Distillation', 'active'),
('PW System India', 'Purified Water', 2, 8000, 'RO + EDI', 'active');

-- Instrument Categories
INSERT INTO instrument_category (name, description) VALUES
('Chromatography', 'HPLC, GC, IC systems'),
('Spectroscopy', 'UV-Vis, IR, NMR'),
('Physical Testing', 'Hardness, friability, dissolution'),
('Weighing', 'Analytical and precision balances'),
('Particle Analysis', 'Particle counters, sizers');

-- Warehouse Zones
INSERT INTO warehouse_zone (site_id, name, zone_type, condition_id, capacity_pallets) VALUES
(1, 'RM Ambient Storage', 'ambient', 1, 500),
(1, 'RM Cold Storage', 'cold', 2, 100),
(1, 'FG Warehouse', 'ambient', 1, 800),
(1, 'Quarantine Zone', 'quarantine', 1, 200),
(2, 'RM Storage India', 'ambient', 1, 1000),
(2, 'FG Warehouse India', 'ambient', 1, 1200);

-- Job Roles
INSERT INTO job_role (title, department_id, grade, description) VALUES
('Production Manager', 1, 'M3', 'Manages manufacturing operations'),
('QC Analyst', 2, 'S2', 'Performs quality control testing'),
('QA Manager', 3, 'M2', 'Manages quality assurance'),
('Warehouse Associate', 4, 'O1', 'Handles warehouse operations'),
('Maintenance Technician', 5, 'T2', 'Equipment maintenance and repair');

-- Vendor Scorecards
INSERT INTO vendor_scorecard (supplier_id, period_start, period_end, quality_score, delivery_score, price_score, service_score, overall_score, lots_received, lots_rejected, on_time_delivery_pct) VALUES
(1, '2025-01-01', '2025-03-31', 4.5, 4.2, 3.8, 4.0, 4.13, 8, 0, 92.0),
(2, '2025-01-01', '2025-03-31', 3.8, 3.5, 4.5, 3.5, 3.83, 5, 1, 80.0),
(3, '2025-01-01', '2025-03-31', 4.8, 4.7, 4.0, 4.5, 4.50, 3, 0, 100.0),
(6, '2025-01-01', '2025-03-31', 4.0, 3.8, 4.2, 3.8, 3.95, 4, 0, 85.0),
(7, '2025-01-01', '2025-03-31', 4.7, 4.5, 3.5, 4.3, 4.25, 2, 0, 100.0);

-- ============================================================
-- Count tables
-- ============================================================
-- Run: SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
