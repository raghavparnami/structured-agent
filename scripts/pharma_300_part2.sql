-- ============================================================
-- Part 2: Additional tables to reach ~300
-- Adds: Batch Genealogy, Serialization, Environmental Compliance,
--        Audit Management, KPI/Metrics, Contract Manufacturing,
--        Technology Transfer, Market Intelligence
-- ============================================================

-- Batch Genealogy & Serialization (~15 tables)

CREATE TABLE batch_genealogy (
    genealogy_id SERIAL PRIMARY KEY,
    parent_batch_id INT REFERENCES batch(batch_id),
    child_batch_id INT REFERENCES batch(batch_id),
    relationship_type VARCHAR(30),        -- split, merge, rework, reprocess
    created_date TIMESTAMP DEFAULT NOW()
);

CREATE TABLE serialization_config (
    config_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    serial_format VARCHAR(100),
    aggregation_levels VARCHAR(200),       -- unit, bundle, case, pallet
    effective_date DATE,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE serial_number (
    serial_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    product_id INT REFERENCES product(product_id),
    serial_number VARCHAR(50) NOT NULL,
    gtin VARCHAR(20),
    level VARCHAR(20),                    -- unit, bundle, case, pallet
    parent_serial_id INT REFERENCES serial_number(serial_id),
    status VARCHAR(20) DEFAULT 'active',  -- active, shipped, recalled, destroyed
    created_date TIMESTAMP DEFAULT NOW()
);

CREATE TABLE serial_event (
    event_id SERIAL PRIMARY KEY,
    serial_id INT REFERENCES serial_number(serial_id),
    event_type VARCHAR(30),               -- commissioning, aggregation, shipping, receiving
    event_date TIMESTAMP NOT NULL,
    location VARCHAR(100),
    performed_by INT REFERENCES employee(employee_id),
    reference_doc VARCHAR(50)
);

CREATE TABLE aggregation (
    aggregation_id SERIAL PRIMARY KEY,
    parent_serial_id INT REFERENCES serial_number(serial_id),
    child_serial_id INT REFERENCES serial_number(serial_id),
    aggregation_date TIMESTAMP DEFAULT NOW(),
    performed_by INT REFERENCES employee(employee_id)
);

-- Environmental Compliance (~10 tables)

CREATE TABLE emission_source (
    source_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    source_name VARCHAR(100) NOT NULL,
    emission_type VARCHAR(50),            -- air, water, solid, noise
    permit_number VARCHAR(50),
    max_allowed NUMERIC(12,4),
    unit VARCHAR(20)
);

CREATE TABLE emission_monitoring (
    monitoring_id SERIAL PRIMARY KEY,
    source_id INT REFERENCES emission_source(source_id),
    monitoring_date TIMESTAMP NOT NULL,
    measured_value NUMERIC(12,4),
    unit VARCHAR(20),
    within_limit BOOLEAN NOT NULL,
    monitored_by INT REFERENCES employee(employee_id)
);

CREATE TABLE waste_manifest (
    manifest_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    manifest_number VARCHAR(50) NOT NULL,
    waste_category_id INT REFERENCES waste_category(waste_category_id),
    generator_name VARCHAR(200),
    transporter_name VARCHAR(200),
    disposal_facility VARCHAR(200),
    ship_date DATE,
    received_date DATE,
    quantity NUMERIC(12,2),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE environmental_permit (
    permit_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    permit_type VARCHAR(50),
    permit_number VARCHAR(50) NOT NULL,
    issuing_authority VARCHAR(200),
    issue_date DATE,
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    conditions TEXT
);

CREATE TABLE environmental_incident (
    incident_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    incident_date TIMESTAMP NOT NULL,
    incident_type VARCHAR(50),            -- spill, leak, exceedance, complaint
    description TEXT NOT NULL,
    environmental_impact TEXT,
    reported_to_authority BOOLEAN DEFAULT FALSE,
    corrective_action TEXT,
    status VARCHAR(20) DEFAULT 'open',
    reported_by INT REFERENCES employee(employee_id)
);

-- Audit Management (~10 tables)

CREATE TABLE audit_schedule (
    schedule_id SERIAL PRIMARY KEY,
    audit_type VARCHAR(50),               -- internal, supplier, process, system
    area_id INT REFERENCES production_area(area_id),
    site_id INT REFERENCES site(site_id),
    planned_date DATE NOT NULL,
    actual_date DATE,
    lead_auditor_id INT REFERENCES employee(employee_id),
    standard_id INT REFERENCES compliance_standard(standard_id),
    status VARCHAR(20) DEFAULT 'planned'
);

CREATE TABLE audit_checklist (
    checklist_id SERIAL PRIMARY KEY,
    audit_type VARCHAR(50),
    standard_id INT REFERENCES compliance_standard(standard_id),
    section VARCHAR(50),
    question TEXT NOT NULL,
    reference_clause VARCHAR(50),
    is_critical BOOLEAN DEFAULT FALSE
);

CREATE TABLE audit_response (
    response_id SERIAL PRIMARY KEY,
    schedule_id INT REFERENCES audit_schedule(schedule_id),
    checklist_id INT REFERENCES audit_checklist(checklist_id),
    response VARCHAR(20),                 -- compliant, non_compliant, observation, na
    evidence TEXT,
    auditor_notes TEXT,
    finding_id INT REFERENCES audit_finding(finding_id)
);

CREATE TABLE audit_report (
    report_id SERIAL PRIMARY KEY,
    schedule_id INT REFERENCES audit_schedule(schedule_id),
    report_date DATE NOT NULL,
    executive_summary TEXT,
    total_observations INT DEFAULT 0,
    critical_findings INT DEFAULT 0,
    major_findings INT DEFAULT 0,
    minor_findings INT DEFAULT 0,
    overall_rating VARCHAR(30),
    approved_by INT REFERENCES employee(employee_id)
);

-- KPI & Metrics Dashboard (~10 tables)

CREATE TABLE kpi_definition (
    kpi_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),                 -- quality, production, safety, compliance, cost
    formula TEXT,
    unit VARCHAR(30),
    target_value NUMERIC(12,4),
    frequency VARCHAR(20),                -- daily, weekly, monthly, quarterly
    owner_id INT REFERENCES employee(employee_id)
);

CREATE TABLE kpi_measurement (
    measurement_id SERIAL PRIMARY KEY,
    kpi_id INT REFERENCES kpi_definition(kpi_id),
    site_id INT REFERENCES site(site_id),
    measurement_date DATE NOT NULL,
    actual_value NUMERIC(12,4),
    target_value NUMERIC(12,4),
    status VARCHAR(20),                   -- on_target, below_target, above_target
    notes TEXT
);

CREATE TABLE dashboard_widget (
    widget_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    widget_type VARCHAR(30),              -- chart, gauge, table, number
    kpi_id INT REFERENCES kpi_definition(kpi_id),
    config_json TEXT,
    display_order INT
);

CREATE TABLE management_review (
    review_id SERIAL PRIMARY KEY,
    review_date DATE NOT NULL,
    site_id INT REFERENCES site(site_id),
    review_type VARCHAR(50),              -- monthly, quarterly, annual
    attendees TEXT,
    minutes TEXT,
    action_items TEXT,
    next_review_date DATE
);

CREATE TABLE quality_metric (
    metric_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    batches_produced INT,
    batches_rejected INT,
    batch_success_rate NUMERIC(5,2),
    deviation_count INT,
    capa_count INT,
    oos_count INT,
    complaint_count INT,
    recall_count INT DEFAULT 0,
    right_first_time_pct NUMERIC(5,2)
);

-- Contract Manufacturing (~10 tables)

CREATE TABLE contract_manufacturer (
    cmo_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    country_id INT REFERENCES country(country_id),
    contact_name VARCHAR(100),
    contact_email VARCHAR(100),
    gmp_certified BOOLEAN DEFAULT TRUE,
    qualification_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    capabilities TEXT
);

CREATE TABLE cmo_agreement (
    agreement_id SERIAL PRIMARY KEY,
    cmo_id INT REFERENCES contract_manufacturer(cmo_id),
    product_id INT REFERENCES product(product_id),
    agreement_type VARCHAR(50),
    start_date DATE,
    end_date DATE,
    min_annual_volume INT,
    price_per_unit NUMERIC(10,4),
    currency_id INT REFERENCES currency(currency_id),
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE cmo_batch (
    cmo_batch_id SERIAL PRIMARY KEY,
    cmo_id INT REFERENCES contract_manufacturer(cmo_id),
    product_id INT REFERENCES product(product_id),
    batch_number VARCHAR(30),
    batch_size NUMERIC(12,2),
    manufacturing_date DATE,
    received_date DATE,
    qc_status VARCHAR(20) DEFAULT 'pending',
    yield_pct NUMERIC(5,2),
    cost NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id)
);

CREATE TABLE cmo_audit (
    audit_id SERIAL PRIMARY KEY,
    cmo_id INT REFERENCES contract_manufacturer(cmo_id),
    audit_date DATE NOT NULL,
    auditor_id INT REFERENCES employee(employee_id),
    audit_type VARCHAR(50),
    score NUMERIC(5,2),
    findings TEXT,
    next_audit_date DATE,
    status VARCHAR(20) DEFAULT 'completed'
);

CREATE TABLE cmo_deviation (
    deviation_id SERIAL PRIMARY KEY,
    cmo_id INT REFERENCES contract_manufacturer(cmo_id),
    cmo_batch_id INT REFERENCES cmo_batch(cmo_batch_id),
    reported_date DATE NOT NULL,
    description TEXT NOT NULL,
    root_cause TEXT,
    capa_required BOOLEAN DEFAULT FALSE,
    status VARCHAR(20) DEFAULT 'open'
);

-- Technology Transfer (~8 tables)

CREATE TABLE tech_transfer (
    transfer_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    from_site_id INT REFERENCES site(site_id),
    to_site_id INT REFERENCES site(site_id),
    transfer_type VARCHAR(30),            -- site_to_site, rd_to_manufacturing, cmo_transfer
    start_date DATE,
    target_date DATE,
    completion_date DATE,
    status VARCHAR(20) DEFAULT 'planned',
    lead_id INT REFERENCES employee(employee_id)
);

CREATE TABLE tech_transfer_milestone (
    milestone_id SERIAL PRIMARY KEY,
    transfer_id INT REFERENCES tech_transfer(transfer_id),
    milestone_name VARCHAR(200) NOT NULL,
    sequence_order INT,
    planned_date DATE,
    actual_date DATE,
    status VARCHAR(20) DEFAULT 'pending',
    owner_id INT REFERENCES employee(employee_id)
);

CREATE TABLE tech_transfer_document (
    doc_id SERIAL PRIMARY KEY,
    transfer_id INT REFERENCES tech_transfer(transfer_id),
    document_id INT REFERENCES document(document_id),
    doc_category VARCHAR(50),             -- process, analytical, packaging, regulatory
    status VARCHAR(20) DEFAULT 'draft'
);

CREATE TABLE tech_transfer_risk (
    risk_id SERIAL PRIMARY KEY,
    transfer_id INT REFERENCES tech_transfer(transfer_id),
    risk_description TEXT NOT NULL,
    likelihood VARCHAR(20),               -- low, medium, high
    impact VARCHAR(20),                   -- low, medium, high
    mitigation TEXT,
    owner_id INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'open'
);

-- Market Intelligence (~8 tables)

CREATE TABLE market_product (
    market_product_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    market_share_pct NUMERIC(5,2),
    annual_revenue NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id),
    report_year INT,
    competitor_count INT
);

CREATE TABLE competitor (
    competitor_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    country_id INT REFERENCES country(country_id),
    market_cap NUMERIC(16,2),
    website VARCHAR(255)
);

CREATE TABLE competitor_product (
    comp_product_id SERIAL PRIMARY KEY,
    competitor_id INT REFERENCES competitor(competitor_id),
    product_name VARCHAR(200),
    therapeutic_area_id INT REFERENCES therapeutic_area(area_id),
    dosage_form_id INT REFERENCES dosage_form(dosage_form_id),
    strength VARCHAR(50),
    launch_date DATE,
    estimated_market_share NUMERIC(5,2)
);

CREATE TABLE pricing (
    pricing_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    price_type VARCHAR(30),               -- wholesale, retail, tender, hospital
    price NUMERIC(12,4),
    currency_id INT REFERENCES currency(currency_id),
    effective_date DATE,
    expiry_date DATE
);

CREATE TABLE tender (
    tender_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    customer_id INT REFERENCES customer(customer_id),
    tender_number VARCHAR(50),
    submission_date DATE,
    quantity INT,
    offered_price NUMERIC(12,4),
    currency_id INT REFERENCES currency(currency_id),
    status VARCHAR(20) DEFAULT 'submitted',  -- submitted, won, lost, cancelled
    result_date DATE
);

-- Sample data for new tables
INSERT INTO contract_manufacturer (name, country_id, contact_name, gmp_certified, status, capabilities) VALUES
('PharmaLink CMO', 2, 'Anand Shah', TRUE, 'active', 'Solid oral dosage, capsules'),
('EuroContract GmbH', 3, 'Franz Huber', TRUE, 'active', 'Sterile injectables, lyophilization'),
('AsiaPharm Manufacturing', 7, 'Li Wei', TRUE, 'active', 'High-volume tablets, packaging');

INSERT INTO competitor (name, country_id) VALUES
('GeneriPharm Inc', 1),
('TevaPharma', 1),
('SunPharma', 2),
('Mylan NV', 1);

INSERT INTO kpi_definition (name, category, formula, unit, target_value, frequency) VALUES
('Batch Success Rate', 'quality', 'approved_batches / total_batches * 100', '%', 95.0, 'monthly'),
('OEE', 'production', 'availability * performance * quality', '%', 85.0, 'daily'),
('Right First Time', 'quality', 'batches_no_deviation / total_batches * 100', '%', 90.0, 'monthly'),
('Scrap Rate', 'quality', 'scrap_qty / total_qty * 100', '%', 3.0, 'monthly'),
('CAPA On-Time Closure', 'compliance', 'on_time_capas / total_capas * 100', '%', 90.0, 'quarterly'),
('Training Compliance', 'compliance', 'trained_employees / total_employees * 100', '%', 95.0, 'monthly');
