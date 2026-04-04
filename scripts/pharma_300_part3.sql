-- Part 3: Final push to ~300 tables
-- Adds: Process Analytics, Data Integrity, Risk Management,
--        Artwork/Packaging Design, Returns, Medical Affairs

-- Process Analytical Technology (PAT) (~10 tables)

CREATE TABLE pat_probe (
    probe_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    probe_type VARCHAR(50),               -- NIR, Raman, particle_size, moisture
    manufacturer VARCHAR(100),
    model VARCHAR(50),
    calibration_date DATE,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE pat_measurement (
    measurement_id SERIAL PRIMARY KEY,
    probe_id INT REFERENCES pat_probe(probe_id),
    batch_id INT REFERENCES batch(batch_id),
    step_id INT REFERENCES process_step(step_id),
    measurement_time TIMESTAMP NOT NULL,
    parameter_name VARCHAR(100),
    value NUMERIC(12,4),
    unit VARCHAR(20),
    within_model BOOLEAN,
    prediction_confidence NUMERIC(5,3)
);

CREATE TABLE pat_model (
    model_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    model_type VARCHAR(50),               -- PLS, PCA, SIMCA, multivariate
    product_id INT REFERENCES product(product_id),
    probe_id INT REFERENCES pat_probe(probe_id),
    version INT DEFAULT 1,
    training_date DATE,
    r_squared NUMERIC(5,4),
    rmse NUMERIC(8,4),
    status VARCHAR(20) DEFAULT 'current'
);

CREATE TABLE real_time_release (
    rtr_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    product_id INT REFERENCES product(product_id),
    parameter_name VARCHAR(100),
    predicted_value NUMERIC(12,4),
    conventional_value NUMERIC(12,4),
    model_id INT REFERENCES pat_model(model_id),
    agreed BOOLEAN,
    release_decision VARCHAR(20)
);

-- Data Integrity (~8 tables)

CREATE TABLE data_integrity_assessment (
    assessment_id SERIAL PRIMARY KEY,
    system_name VARCHAR(200) NOT NULL,
    assessment_date DATE NOT NULL,
    assessor_id INT REFERENCES employee(employee_id),
    alcoa_plus_score NUMERIC(5,2),        -- Attributable, Legible, Contemporaneous, Original, Accurate
    risk_level VARCHAR(20),
    findings TEXT,
    recommendations TEXT,
    status VARCHAR(20) DEFAULT 'completed'
);

CREATE TABLE electronic_record (
    record_id SERIAL PRIMARY KEY,
    system_name VARCHAR(100),
    record_type VARCHAR(50),
    record_date TIMESTAMP NOT NULL,
    created_by INT REFERENCES employee(employee_id),
    modified_by INT REFERENCES employee(employee_id),
    modified_date TIMESTAMP,
    version INT DEFAULT 1,
    is_locked BOOLEAN DEFAULT FALSE,
    hash_value VARCHAR(64)
);

CREATE TABLE access_control (
    access_id SERIAL PRIMARY KEY,
    system_name VARCHAR(100) NOT NULL,
    employee_id INT REFERENCES employee(employee_id),
    role_name VARCHAR(50),
    access_level VARCHAR(20),             -- read, write, admin, approve
    granted_date DATE,
    revoked_date DATE,
    granted_by INT REFERENCES employee(employee_id)
);

CREATE TABLE backup_log (
    backup_id SERIAL PRIMARY KEY,
    system_name VARCHAR(100) NOT NULL,
    backup_date TIMESTAMP NOT NULL,
    backup_type VARCHAR(20),              -- full, incremental, differential
    size_gb NUMERIC(8,2),
    location VARCHAR(200),
    verified BOOLEAN DEFAULT FALSE,
    verified_by INT REFERENCES employee(employee_id)
);

-- Risk Management (~8 tables)

CREATE TABLE risk_assessment (
    assessment_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    risk_type VARCHAR(50),                -- process, product, facility, supply_chain
    product_id INT REFERENCES product(product_id),
    site_id INT REFERENCES site(site_id),
    assessment_date DATE NOT NULL,
    methodology VARCHAR(50),              -- FMEA, HACCP, FTA, PHA
    status VARCHAR(20) DEFAULT 'active',
    owner_id INT REFERENCES employee(employee_id)
);

CREATE TABLE risk_item (
    item_id SERIAL PRIMARY KEY,
    assessment_id INT REFERENCES risk_assessment(assessment_id),
    risk_description TEXT NOT NULL,
    cause TEXT,
    effect TEXT,
    severity INT,                         -- 1-10
    occurrence INT,                       -- 1-10
    detectability INT,                    -- 1-10
    rpn INT,                              -- severity × occurrence × detectability
    risk_level VARCHAR(20),               -- low, medium, high, critical
    mitigation TEXT,
    residual_rpn INT,
    owner_id INT REFERENCES employee(employee_id)
);

CREATE TABLE risk_review (
    review_id SERIAL PRIMARY KEY,
    assessment_id INT REFERENCES risk_assessment(assessment_id),
    review_date DATE NOT NULL,
    reviewed_by INT REFERENCES employee(employee_id),
    changes_made TEXT,
    next_review_date DATE
);

-- Artwork & Packaging Design (~8 tables)

CREATE TABLE artwork (
    artwork_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    artwork_type VARCHAR(50),             -- label, carton, leaflet, blister_foil
    version INT DEFAULT 1,
    status VARCHAR(20) DEFAULT 'draft',
    created_by INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id),
    effective_date DATE,
    file_path VARCHAR(255)
);

CREATE TABLE artwork_approval (
    approval_id SERIAL PRIMARY KEY,
    artwork_id INT REFERENCES artwork(artwork_id),
    approver_id INT REFERENCES employee(employee_id),
    approval_stage VARCHAR(50),           -- regulatory, marketing, qa, legal
    decision VARCHAR(20),                 -- approved, rejected, needs_changes
    comments TEXT,
    approval_date TIMESTAMP
);

CREATE TABLE packaging_specification (
    spec_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    packaging_type_id INT REFERENCES packaging_type(packaging_type_id),
    pack_size INT,
    shipper_size INT,
    shelf_life_months INT,
    version INT DEFAULT 1,
    status VARCHAR(20) DEFAULT 'current',
    effective_date DATE
);

CREATE TABLE packaging_component (
    component_id SERIAL PRIMARY KEY,
    spec_id INT REFERENCES packaging_specification(spec_id),
    component_name VARCHAR(100),
    material_id INT REFERENCES raw_material(material_id),
    quantity_per_pack NUMERIC(8,2),
    is_primary BOOLEAN DEFAULT FALSE,
    supplier_id INT REFERENCES supplier(supplier_id)
);

-- Returns & Recalls (~6 tables)

CREATE TABLE product_return (
    return_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customer(customer_id),
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    return_date DATE NOT NULL,
    quantity INT NOT NULL,
    reason VARCHAR(200),
    condition VARCHAR(50),                -- damaged, expired, quality_issue, other
    disposition VARCHAR(30),              -- restock, destroy, quarantine, return_to_mfg
    credit_amount NUMERIC(14,2),
    processed_by INT REFERENCES employee(employee_id)
);

CREATE TABLE recall_batch (
    recall_batch_id SERIAL PRIMARY KEY,
    recall_id INT REFERENCES product_recall(recall_id),
    batch_id INT REFERENCES batch(batch_id),
    quantity_distributed INT,
    quantity_recovered INT DEFAULT 0,
    recovery_pct NUMERIC(5,2),
    customer_notified BOOLEAN DEFAULT FALSE
);

CREATE TABLE recall_communication (
    comm_id SERIAL PRIMARY KEY,
    recall_id INT REFERENCES product_recall(recall_id),
    communication_type VARCHAR(50),       -- customer_letter, press_release, regulatory_notice
    sent_date DATE,
    recipient VARCHAR(200),
    content TEXT,
    sent_by INT REFERENCES employee(employee_id)
);

-- Medical Affairs (~6 tables)

CREATE TABLE medical_information_request (
    mir_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    request_date DATE NOT NULL,
    requester_type VARCHAR(50),           -- physician, pharmacist, patient, regulatory
    question TEXT NOT NULL,
    response TEXT,
    responded_date DATE,
    responded_by INT REFERENCES employee(employee_id),
    category VARCHAR(50),
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE publication (
    publication_id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    product_id INT REFERENCES product(product_id),
    trial_id INT REFERENCES clinical_trial(trial_id),
    journal_name VARCHAR(200),
    publication_date DATE,
    publication_type VARCHAR(50),         -- original_research, review, case_report, poster
    doi VARCHAR(100),
    status VARCHAR(20) DEFAULT 'published'
);

CREATE TABLE key_opinion_leader (
    kol_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    speciality VARCHAR(100),
    institution VARCHAR(200),
    country_id INT REFERENCES country(country_id),
    engagement_level VARCHAR(20),         -- advisory_board, speaker, investigator, consultant
    therapeutic_area_id INT REFERENCES therapeutic_area(area_id)
);

CREATE TABLE medical_event (
    event_id SERIAL PRIMARY KEY,
    event_name VARCHAR(200) NOT NULL,
    event_type VARCHAR(50),               -- congress, symposium, advisory_board, webinar
    start_date DATE,
    end_date DATE,
    location VARCHAR(200),
    country_id INT REFERENCES country(country_id),
    budget NUMERIC(14,2),
    therapeutic_area_id INT REFERENCES therapeutic_area(area_id),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE medical_event_attendee (
    attendee_id SERIAL PRIMARY KEY,
    event_id INT REFERENCES medical_event(event_id),
    kol_id INT REFERENCES key_opinion_leader(kol_id),
    employee_id INT REFERENCES employee(employee_id),
    role VARCHAR(50),                     -- speaker, attendee, organizer, sponsor_rep
    travel_cost NUMERIC(10,2)
);

-- Sample KPI measurements
INSERT INTO kpi_measurement (kpi_id, site_id, measurement_date, actual_value, target_value, status) VALUES
(1, 1, '2025-01-31', 93.3, 95.0, 'below_target'),
(1, 1, '2025-02-28', 100.0, 95.0, 'on_target'),
(1, 1, '2025-03-31', 50.0, 95.0, 'below_target'),
(1, 2, '2025-01-31', 100.0, 95.0, 'on_target'),
(1, 2, '2025-02-28', 100.0, 95.0, 'on_target'),
(4, 1, '2025-01-31', 2.4, 3.0, 'on_target'),
(4, 1, '2025-02-28', 1.0, 3.0, 'on_target'),
(4, 1, '2025-03-31', 24.0, 3.0, 'below_target');

INSERT INTO quality_metric (site_id, period_start, period_end, batches_produced, batches_rejected, batch_success_rate, deviation_count, capa_count, oos_count, complaint_count, right_first_time_pct) VALUES
(1, '2025-01-01', '2025-03-31', 8, 2, 75.0, 3, 4, 2, 1, 62.5),
(2, '2025-01-01', '2025-03-31', 5, 0, 100.0, 1, 1, 0, 1, 80.0);
