-- ============================================================
-- Pharma Manufacturing Database (~150 tables)
-- Covers: Production, Materials, Equipment, QC, Scrap/Waste,
--         Personnel, Compliance, Inventory, Suppliers, Packaging
-- ============================================================

-- Run: psql -U postgres -f scripts/pharma_manufacturing_db.sql

DROP DATABASE IF EXISTS pharma_manufacturing;
CREATE DATABASE pharma_manufacturing;
\c pharma_manufacturing

-- ============================================================
-- SCHEMA: Reference / Lookup Tables (~30 tables)
-- ============================================================

CREATE TABLE product_category (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE dosage_form (
    dosage_form_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,  -- tablet, capsule, injection, syrup, cream
    description TEXT
);

CREATE TABLE unit_of_measure (
    uom_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL,   -- kg, g, mg, L, mL, unit
    name VARCHAR(100) NOT NULL,
    uom_type VARCHAR(20) NOT NULL  -- weight, volume, count
);

CREATE TABLE currency (
    currency_id SERIAL PRIMARY KEY,
    code VARCHAR(3) NOT NULL,
    name VARCHAR(50) NOT NULL,
    exchange_rate_to_usd NUMERIC(12,6) DEFAULT 1.0
);

CREATE TABLE country (
    country_id SERIAL PRIMARY KEY,
    code VARCHAR(3) NOT NULL,
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50)
);

CREATE TABLE regulatory_body (
    body_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,        -- FDA, EMA, CDSCO, PMDA
    country_id INT REFERENCES country(country_id),
    website VARCHAR(255)
);

CREATE TABLE compliance_standard (
    standard_id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL,          -- GMP, ISO 13485, ICH Q7
    name VARCHAR(200) NOT NULL,
    body_id INT REFERENCES regulatory_body(body_id),
    effective_date DATE
);

CREATE TABLE shift_type (
    shift_type_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,          -- Morning, Afternoon, Night
    start_time TIME NOT NULL,
    end_time TIME NOT NULL
);

CREATE TABLE equipment_type (
    equipment_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- Mixer, Granulator, Tablet Press, Coater
    category VARCHAR(50),               -- processing, packaging, testing
    description TEXT
);

CREATE TABLE defect_type (
    defect_type_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,         -- Capping, Chipping, Weight Variation, Discoloration
    severity VARCHAR(20) NOT NULL,      -- critical, major, minor
    description TEXT
);

CREATE TABLE scrap_reason (
    reason_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,      -- material, equipment, process, human, environmental
    description TEXT
);

CREATE TABLE waste_category (
    waste_category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- hazardous, non-hazardous, recyclable
    disposal_method VARCHAR(100),
    regulatory_code VARCHAR(50)
);

CREATE TABLE test_type (
    test_type_id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,         -- Dissolution, Hardness, Friability, Assay, Microbial
    category VARCHAR(50),               -- physical, chemical, microbiological
    description TEXT
);

CREATE TABLE specification_type (
    spec_type_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,          -- raw_material, in_process, finished_product, stability
    description TEXT
);

CREATE TABLE storage_condition (
    condition_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- Room Temp, Cold Chain, Frozen, Controlled
    min_temp_c NUMERIC(5,1),
    max_temp_c NUMERIC(5,1),
    min_humidity_pct NUMERIC(5,1),
    max_humidity_pct NUMERIC(5,1)
);

CREATE TABLE packaging_type (
    packaging_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- Blister, Bottle, Vial, Ampoule, Sachet
    material VARCHAR(100),
    description TEXT
);

CREATE TABLE deviation_type (
    deviation_type_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,         -- Process, Equipment, Material, Environmental
    severity VARCHAR(20) NOT NULL,      -- critical, major, minor
    requires_capa BOOLEAN DEFAULT FALSE
);

CREATE TABLE capa_type (
    capa_type_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,          -- Corrective, Preventive
    description TEXT
);

CREATE TABLE document_type (
    doc_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,         -- SOP, Batch Record, CoA, Deviation Report
    retention_years INT DEFAULT 7
);

CREATE TABLE approval_status (
    status_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL            -- Draft, Pending Review, Approved, Rejected, Superseded
);

CREATE TABLE material_class (
    class_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,          -- API, Excipient, Solvent, Packaging Material
    description TEXT,
    requires_coa BOOLEAN DEFAULT TRUE
);

CREATE TABLE allergen (
    allergen_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,          -- Lactose, Gluten, Soy, Gelatin
    description TEXT
);

CREATE TABLE environmental_zone (
    zone_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,           -- Grade A, Grade B, Grade C, Grade D, Unclassified
    max_particles_05um INT,
    max_particles_5um INT,
    description TEXT
);

CREATE TABLE maintenance_type (
    maintenance_type_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,           -- Preventive, Corrective, Calibration
    frequency_days INT,
    description TEXT
);

CREATE TABLE training_type (
    training_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,          -- GMP, Equipment Operation, Safety, SOP-specific
    required_for VARCHAR(100),
    validity_months INT DEFAULT 12
);

CREATE TABLE cost_center (
    cost_center_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    department VARCHAR(50)
);

CREATE TABLE priority_level (
    priority_id SERIAL PRIMARY KEY,
    name VARCHAR(20) NOT NULL,           -- Low, Medium, High, Critical
    sla_hours INT
);

-- ============================================================
-- SCHEMA: Organizational (~15 tables)
-- ============================================================

CREATE TABLE site (
    site_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(20) NOT NULL,
    country_id INT REFERENCES country(country_id),
    address TEXT,
    gmp_certified BOOLEAN DEFAULT TRUE,
    max_capacity_units_per_day INT
);

CREATE TABLE building (
    building_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    name VARCHAR(100) NOT NULL,
    zone_id INT REFERENCES environmental_zone(zone_id),
    floor_area_sqm NUMERIC(10,2)
);

CREATE TABLE production_area (
    area_id SERIAL PRIMARY KEY,
    building_id INT REFERENCES building(building_id),
    name VARCHAR(100) NOT NULL,
    zone_id INT REFERENCES environmental_zone(zone_id),
    area_type VARCHAR(50),             -- manufacturing, packaging, storage, lab
    max_concurrent_batches INT DEFAULT 1
);

CREATE TABLE department (
    department_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    name VARCHAR(100) NOT NULL,
    cost_center_id INT REFERENCES cost_center(cost_center_id)
);

CREATE TABLE employee (
    employee_id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department_id INT REFERENCES department(department_id),
    site_id INT REFERENCES site(site_id),
    job_title VARCHAR(100),
    hire_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    email VARCHAR(100),
    supervisor_id INT REFERENCES employee(employee_id)
);

CREATE TABLE employee_qualification (
    qualification_id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employee(employee_id),
    training_type_id INT REFERENCES training_type(training_type_id),
    qualified_date DATE NOT NULL,
    expiry_date DATE,
    certified_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE shift_schedule (
    schedule_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    shift_type_id INT REFERENCES shift_type(shift_type_id),
    effective_from DATE NOT NULL,
    effective_to DATE,
    headcount INT
);

CREATE TABLE production_line (
    line_id SERIAL PRIMARY KEY,
    area_id INT REFERENCES production_area(area_id),
    name VARCHAR(100) NOT NULL,
    line_type VARCHAR(50),             -- tablet, capsule, liquid, injectable
    max_speed_units_per_hour INT,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE work_center (
    work_center_id SERIAL PRIMARY KEY,
    line_id INT REFERENCES production_line(line_id),
    name VARCHAR(100) NOT NULL,
    process_step VARCHAR(100),         -- dispensing, granulation, compression, coating, packaging
    sequence_order INT
);

-- ============================================================
-- SCHEMA: Equipment (~12 tables)
-- ============================================================

CREATE TABLE equipment (
    equipment_id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    equipment_type_id INT REFERENCES equipment_type(equipment_type_id),
    work_center_id INT REFERENCES work_center(work_center_id),
    manufacturer VARCHAR(100),
    model_number VARCHAR(50),
    serial_number VARCHAR(50),
    install_date DATE,
    status VARCHAR(20) DEFAULT 'active',  -- active, maintenance, decommissioned
    last_calibration_date DATE,
    next_calibration_date DATE
);

CREATE TABLE equipment_sensor (
    sensor_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    sensor_type VARCHAR(50) NOT NULL,   -- temperature, pressure, humidity, speed, weight
    unit VARCHAR(20),
    min_range NUMERIC(12,4),
    max_range NUMERIC(12,4),
    calibration_interval_days INT
);

CREATE TABLE equipment_maintenance (
    maintenance_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    maintenance_type_id INT REFERENCES maintenance_type(maintenance_type_id),
    scheduled_date DATE NOT NULL,
    completed_date DATE,
    performed_by INT REFERENCES employee(employee_id),
    findings TEXT,
    parts_replaced TEXT,
    cost NUMERIC(12,2),
    status VARCHAR(20) DEFAULT 'scheduled'
);

CREATE TABLE equipment_downtime (
    downtime_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    reason VARCHAR(200),
    category VARCHAR(50),              -- planned, unplanned, changeover
    impact_batches INT DEFAULT 0,
    reported_by INT REFERENCES employee(employee_id)
);

CREATE TABLE equipment_cleaning (
    cleaning_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    cleaning_date TIMESTAMP NOT NULL,
    cleaning_type VARCHAR(50),         -- major, minor, line_clearance
    cleaned_by INT REFERENCES employee(employee_id),
    verified_by INT REFERENCES employee(employee_id),
    swab_test_passed BOOLEAN,
    next_use_deadline TIMESTAMP
);

CREATE TABLE calibration_record (
    calibration_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    sensor_id INT REFERENCES equipment_sensor(sensor_id),
    calibration_date TIMESTAMP NOT NULL,
    performed_by INT REFERENCES employee(employee_id),
    standard_used VARCHAR(100),
    reading_before NUMERIC(12,4),
    reading_after NUMERIC(12,4),
    tolerance NUMERIC(12,4),
    passed BOOLEAN NOT NULL,
    certificate_number VARCHAR(50)
);

CREATE TABLE equipment_logbook (
    log_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    log_date TIMESTAMP DEFAULT NOW(),
    logged_by INT REFERENCES employee(employee_id),
    event_type VARCHAR(50),            -- usage, cleaning, issue, note
    description TEXT,
    batch_id INT  -- FK added later
);

CREATE TABLE spare_part (
    part_id SERIAL PRIMARY KEY,
    equipment_type_id INT REFERENCES equipment_type(equipment_type_id),
    part_number VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    lead_time_days INT,
    reorder_point INT DEFAULT 2,
    current_stock INT DEFAULT 0,
    unit_cost NUMERIC(12,2)
);

CREATE TABLE spare_part_usage (
    usage_id SERIAL PRIMARY KEY,
    part_id INT REFERENCES spare_part(part_id),
    maintenance_id INT REFERENCES equipment_maintenance(maintenance_id),
    quantity_used INT NOT NULL,
    usage_date DATE DEFAULT CURRENT_DATE
);

-- ============================================================
-- SCHEMA: Materials & Suppliers (~18 tables)
-- ============================================================

CREATE TABLE supplier (
    supplier_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    code VARCHAR(20) NOT NULL,
    country_id INT REFERENCES country(country_id),
    contact_name VARCHAR(100),
    contact_email VARCHAR(100),
    phone VARCHAR(30),
    is_approved BOOLEAN DEFAULT FALSE,
    approval_date DATE,
    rating NUMERIC(3,1),               -- 1.0 to 5.0
    gmp_certified BOOLEAN DEFAULT FALSE
);

CREATE TABLE supplier_audit (
    audit_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    audit_date DATE NOT NULL,
    auditor_id INT REFERENCES employee(employee_id),
    audit_type VARCHAR(50),            -- initial, periodic, for_cause
    score NUMERIC(5,2),
    findings TEXT,
    status VARCHAR(20) DEFAULT 'completed',
    next_audit_date DATE
);

CREATE TABLE raw_material (
    material_id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(200) NOT NULL,
    class_id INT REFERENCES material_class(class_id),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    storage_condition_id INT REFERENCES storage_condition(condition_id),
    shelf_life_months INT,
    reorder_point NUMERIC(12,2),
    safety_stock NUMERIC(12,2),
    is_controlled BOOLEAN DEFAULT FALSE,
    cas_number VARCHAR(30),
    description TEXT
);

CREATE TABLE material_allergen (
    material_id INT REFERENCES raw_material(material_id),
    allergen_id INT REFERENCES allergen(allergen_id),
    PRIMARY KEY (material_id, allergen_id)
);

CREATE TABLE supplier_material (
    supplier_material_id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES supplier(supplier_id),
    material_id INT REFERENCES raw_material(material_id),
    supplier_part_number VARCHAR(50),
    lead_time_days INT,
    min_order_qty NUMERIC(12,2),
    unit_price NUMERIC(12,4),
    currency_id INT REFERENCES currency(currency_id),
    is_primary BOOLEAN DEFAULT FALSE,
    qualification_date DATE
);

CREATE TABLE purchase_order (
    po_id SERIAL PRIMARY KEY,
    po_number VARCHAR(30) NOT NULL,
    supplier_id INT REFERENCES supplier(supplier_id),
    order_date DATE NOT NULL,
    expected_delivery_date DATE,
    actual_delivery_date DATE,
    status VARCHAR(20) DEFAULT 'open',  -- open, partial, received, cancelled
    total_amount NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id),
    created_by INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id)
);

CREATE TABLE purchase_order_line (
    po_line_id SERIAL PRIMARY KEY,
    po_id INT REFERENCES purchase_order(po_id),
    material_id INT REFERENCES raw_material(material_id),
    quantity_ordered NUMERIC(12,2) NOT NULL,
    unit_price NUMERIC(12,4) NOT NULL,
    quantity_received NUMERIC(12,2) DEFAULT 0,
    line_total NUMERIC(14,2)
);

CREATE TABLE material_receipt (
    receipt_id SERIAL PRIMARY KEY,
    po_id INT REFERENCES purchase_order(po_id),
    receipt_date TIMESTAMP NOT NULL,
    received_by INT REFERENCES employee(employee_id),
    delivery_note_number VARCHAR(50),
    status VARCHAR(20) DEFAULT 'quarantine'  -- quarantine, approved, rejected
);

CREATE TABLE material_receipt_line (
    receipt_line_id SERIAL PRIMARY KEY,
    receipt_id INT REFERENCES material_receipt(receipt_id),
    material_id INT REFERENCES raw_material(material_id),
    lot_number VARCHAR(50) NOT NULL,
    quantity_received NUMERIC(12,2) NOT NULL,
    manufacturing_date DATE,
    expiry_date DATE,
    coa_received BOOLEAN DEFAULT FALSE,
    storage_location VARCHAR(50)
);

CREATE TABLE material_lot (
    lot_id SERIAL PRIMARY KEY,
    material_id INT REFERENCES raw_material(material_id),
    lot_number VARCHAR(50) NOT NULL,
    receipt_line_id INT REFERENCES material_receipt_line(receipt_line_id),
    quantity_received NUMERIC(12,2) NOT NULL,
    quantity_available NUMERIC(12,2) NOT NULL,
    quantity_consumed NUMERIC(12,2) DEFAULT 0,
    quantity_rejected NUMERIC(12,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'quarantine',  -- quarantine, approved, rejected, expired, consumed
    manufacturing_date DATE,
    expiry_date DATE,
    supplier_id INT REFERENCES supplier(supplier_id),
    warehouse_location VARCHAR(50),
    approved_date DATE,
    approved_by INT REFERENCES employee(employee_id)
);

CREATE TABLE material_lot_test (
    test_id SERIAL PRIMARY KEY,
    lot_id INT REFERENCES material_lot(lot_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    test_date TIMESTAMP NOT NULL,
    tested_by INT REFERENCES employee(employee_id),
    result_value NUMERIC(12,4),
    result_text VARCHAR(200),
    spec_min NUMERIC(12,4),
    spec_max NUMERIC(12,4),
    passed BOOLEAN NOT NULL,
    instrument_id INT REFERENCES equipment(equipment_id)
);

CREATE TABLE material_lot_transaction (
    transaction_id SERIAL PRIMARY KEY,
    lot_id INT REFERENCES material_lot(lot_id),
    transaction_type VARCHAR(20) NOT NULL,  -- receive, dispense, return, adjust, reject
    quantity NUMERIC(12,2) NOT NULL,
    transaction_date TIMESTAMP DEFAULT NOW(),
    performed_by INT REFERENCES employee(employee_id),
    batch_id INT,  -- FK added later
    reference_doc VARCHAR(50),
    notes TEXT
);

-- ============================================================
-- SCHEMA: Products & Formulations (~12 tables)
-- ============================================================

CREATE TABLE product (
    product_id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(200) NOT NULL,
    category_id INT REFERENCES product_category(category_id),
    dosage_form_id INT REFERENCES dosage_form(dosage_form_id),
    strength VARCHAR(50),              -- e.g., "500mg", "10mg/mL"
    shelf_life_months INT,
    storage_condition_id INT REFERENCES storage_condition(condition_id),
    status VARCHAR(20) DEFAULT 'active',
    launch_date DATE,
    description TEXT
);

CREATE TABLE product_registration (
    registration_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    country_id INT REFERENCES country(country_id),
    body_id INT REFERENCES regulatory_body(body_id),
    registration_number VARCHAR(50),
    approval_date DATE,
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE bill_of_materials (
    bom_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    effective_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    approved_by INT REFERENCES employee(employee_id),
    batch_size NUMERIC(12,2) NOT NULL,
    batch_size_uom_id INT REFERENCES unit_of_measure(uom_id)
);

CREATE TABLE bom_line (
    bom_line_id SERIAL PRIMARY KEY,
    bom_id INT REFERENCES bill_of_materials(bom_id),
    material_id INT REFERENCES raw_material(material_id),
    quantity_per_batch NUMERIC(12,4) NOT NULL,
    uom_id INT REFERENCES unit_of_measure(uom_id),
    overage_pct NUMERIC(5,2) DEFAULT 0,
    is_active_ingredient BOOLEAN DEFAULT FALSE,
    sequence_order INT
);

CREATE TABLE master_batch_record (
    mbr_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    version INT DEFAULT 1,
    bom_id INT REFERENCES bill_of_materials(bom_id),
    effective_date DATE NOT NULL,
    status_id INT REFERENCES approval_status(status_id),
    approved_by INT REFERENCES employee(employee_id),
    total_process_steps INT,
    expected_yield_pct NUMERIC(5,2) DEFAULT 95.0,
    document_number VARCHAR(50)
);

CREATE TABLE process_step (
    step_id SERIAL PRIMARY KEY,
    mbr_id INT REFERENCES master_batch_record(mbr_id),
    step_number INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    work_center_id INT REFERENCES work_center(work_center_id),
    expected_duration_minutes INT,
    critical_step BOOLEAN DEFAULT FALSE,
    in_process_checks TEXT
);

CREATE TABLE process_parameter (
    parameter_id SERIAL PRIMARY KEY,
    step_id INT REFERENCES process_step(step_id),
    name VARCHAR(100) NOT NULL,          -- temperature, pressure, speed, time
    target_value NUMERIC(12,4),
    min_value NUMERIC(12,4),
    max_value NUMERIC(12,4),
    uom_id INT REFERENCES unit_of_measure(uom_id),
    is_critical BOOLEAN DEFAULT FALSE
);

CREATE TABLE product_specification (
    spec_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    spec_type_id INT REFERENCES specification_type(spec_type_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    parameter_name VARCHAR(100) NOT NULL,
    spec_min NUMERIC(12,4),
    spec_max NUMERIC(12,4),
    spec_target NUMERIC(12,4),
    spec_text VARCHAR(200),
    version INT DEFAULT 1,
    effective_date DATE
);

-- ============================================================
-- SCHEMA: Production & Batch (~15 tables)
-- ============================================================

CREATE TABLE production_order (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(30) NOT NULL,
    product_id INT REFERENCES product(product_id),
    site_id INT REFERENCES site(site_id),
    line_id INT REFERENCES production_line(line_id),
    planned_quantity NUMERIC(12,2) NOT NULL,
    planned_start_date DATE,
    planned_end_date DATE,
    actual_start_date DATE,
    actual_end_date DATE,
    status VARCHAR(20) DEFAULT 'planned',  -- planned, in_progress, completed, cancelled
    priority_id INT REFERENCES priority_level(priority_id),
    created_by INT REFERENCES employee(employee_id),
    mbr_id INT REFERENCES master_batch_record(mbr_id)
);

CREATE TABLE batch (
    batch_id SERIAL PRIMARY KEY,
    batch_number VARCHAR(30) NOT NULL,
    order_id INT REFERENCES production_order(order_id),
    product_id INT REFERENCES product(product_id),
    site_id INT REFERENCES site(site_id),
    line_id INT REFERENCES production_line(line_id),
    bom_id INT REFERENCES bill_of_materials(bom_id),
    batch_size NUMERIC(12,2) NOT NULL,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    status VARCHAR(20) DEFAULT 'planned',  -- planned, dispensing, in_process, packaging, qa_hold, approved, rejected, shipped
    yield_quantity NUMERIC(12,2),
    yield_pct NUMERIC(5,2),
    shift_type_id INT REFERENCES shift_type(shift_type_id),
    supervisor_id INT REFERENCES employee(employee_id),
    released_by INT REFERENCES employee(employee_id),
    released_date TIMESTAMP
);

-- Add FK from equipment_logbook and material_lot_transaction to batch
ALTER TABLE equipment_logbook ADD CONSTRAINT fk_logbook_batch FOREIGN KEY (batch_id) REFERENCES batch(batch_id);
ALTER TABLE material_lot_transaction ADD CONSTRAINT fk_lot_txn_batch FOREIGN KEY (batch_id) REFERENCES batch(batch_id);

CREATE TABLE batch_step_execution (
    execution_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    step_id INT REFERENCES process_step(step_id),
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    performed_by INT REFERENCES employee(employee_id),
    verified_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'pending',  -- pending, in_progress, completed, failed
    equipment_id INT REFERENCES equipment(equipment_id),
    notes TEXT
);

CREATE TABLE batch_parameter_reading (
    reading_id SERIAL PRIMARY KEY,
    execution_id INT REFERENCES batch_step_execution(execution_id),
    parameter_id INT REFERENCES process_parameter(parameter_id),
    reading_time TIMESTAMP NOT NULL,
    actual_value NUMERIC(12,4) NOT NULL,
    within_spec BOOLEAN NOT NULL,
    recorded_by INT REFERENCES employee(employee_id),
    sensor_id INT REFERENCES equipment_sensor(sensor_id)
);

CREATE TABLE batch_material_usage (
    usage_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    material_id INT REFERENCES raw_material(material_id),
    lot_id INT REFERENCES material_lot(lot_id),
    step_id INT REFERENCES process_step(step_id),
    planned_quantity NUMERIC(12,4),
    actual_quantity NUMERIC(12,4) NOT NULL,
    uom_id INT REFERENCES unit_of_measure(uom_id),
    dispensed_by INT REFERENCES employee(employee_id),
    dispensed_at TIMESTAMP DEFAULT NOW(),
    verified_by INT REFERENCES employee(employee_id)
);

CREATE TABLE batch_yield (
    yield_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    stage VARCHAR(50) NOT NULL,        -- granulation, compression, coating, packaging
    input_quantity NUMERIC(12,2),
    output_quantity NUMERIC(12,2),
    waste_quantity NUMERIC(12,2),
    yield_pct NUMERIC(5,2),
    measured_by INT REFERENCES employee(employee_id),
    measured_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE in_process_check (
    check_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    execution_id INT REFERENCES batch_step_execution(execution_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    check_time TIMESTAMP NOT NULL,
    sample_size INT,
    result_value NUMERIC(12,4),
    result_text VARCHAR(200),
    spec_min NUMERIC(12,4),
    spec_max NUMERIC(12,4),
    passed BOOLEAN NOT NULL,
    checked_by INT REFERENCES employee(employee_id),
    instrument_id INT REFERENCES equipment(equipment_id)
);

CREATE TABLE batch_hold (
    hold_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    hold_date TIMESTAMP NOT NULL,
    hold_reason TEXT NOT NULL,
    hold_type VARCHAR(50),             -- qa_hold, investigation, customer_complaint
    released_date TIMESTAMP,
    released_by INT REFERENCES employee(employee_id),
    disposition VARCHAR(20),           -- release, reject, rework, reprocess
    notes TEXT
);

CREATE TABLE batch_rework (
    rework_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    hold_id INT REFERENCES batch_hold(hold_id),
    rework_type VARCHAR(50),           -- reprocess, reblend, recoat, repack
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    performed_by INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id),
    additional_cost NUMERIC(12,2),
    result VARCHAR(20)                 -- passed, failed
);

CREATE TABLE batch_cost (
    cost_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    cost_type VARCHAR(50) NOT NULL,    -- material, labor, overhead, energy, scrap
    amount NUMERIC(14,2) NOT NULL,
    currency_id INT REFERENCES currency(currency_id),
    cost_center_id INT REFERENCES cost_center(cost_center_id),
    recorded_date DATE DEFAULT CURRENT_DATE,
    notes TEXT
);

CREATE TABLE batch_comment (
    comment_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    comment_date TIMESTAMP DEFAULT NOW(),
    commented_by INT REFERENCES employee(employee_id),
    comment_type VARCHAR(50),          -- note, issue, observation
    comment_text TEXT NOT NULL
);

-- ============================================================
-- SCHEMA: Scrap & Waste (~10 tables)
-- ============================================================

CREATE TABLE scrap_event (
    scrap_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    step_id INT REFERENCES process_step(step_id),
    equipment_id INT REFERENCES equipment(equipment_id),
    reason_id INT REFERENCES scrap_reason(reason_id),
    scrap_date TIMESTAMP NOT NULL,
    quantity NUMERIC(12,2) NOT NULL,
    uom_id INT REFERENCES unit_of_measure(uom_id),
    cost_impact NUMERIC(12,2),
    reported_by INT REFERENCES employee(employee_id),
    shift_type_id INT REFERENCES shift_type(shift_type_id),
    description TEXT,
    root_cause TEXT,
    corrective_action TEXT
);

CREATE TABLE scrap_material_detail (
    detail_id SERIAL PRIMARY KEY,
    scrap_id INT REFERENCES scrap_event(scrap_id),
    material_id INT REFERENCES raw_material(material_id),
    lot_id INT REFERENCES material_lot(lot_id),
    quantity_scrapped NUMERIC(12,2) NOT NULL,
    unit_cost NUMERIC(12,4),
    total_cost NUMERIC(12,2)
);

CREATE TABLE scrap_investigation (
    investigation_id SERIAL PRIMARY KEY,
    scrap_id INT REFERENCES scrap_event(scrap_id),
    investigator_id INT REFERENCES employee(employee_id),
    start_date DATE NOT NULL,
    end_date DATE,
    root_cause_category VARCHAR(50),   -- 5-why, fishbone, fault_tree
    root_cause_detail TEXT,
    contributing_factors TEXT,
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE waste_disposal (
    disposal_id SERIAL PRIMARY KEY,
    waste_category_id INT REFERENCES waste_category(waste_category_id),
    batch_id INT REFERENCES batch(batch_id),
    scrap_id INT REFERENCES scrap_event(scrap_id),
    disposal_date TIMESTAMP NOT NULL,
    quantity NUMERIC(12,2) NOT NULL,
    uom_id INT REFERENCES unit_of_measure(uom_id),
    disposal_method VARCHAR(100),
    disposal_vendor VARCHAR(100),
    manifest_number VARCHAR(50),
    cost NUMERIC(12,2),
    handled_by INT REFERENCES employee(employee_id)
);

CREATE TABLE environmental_monitoring (
    monitoring_id SERIAL PRIMARY KEY,
    area_id INT REFERENCES production_area(area_id),
    monitoring_date TIMESTAMP NOT NULL,
    temperature_c NUMERIC(5,1),
    humidity_pct NUMERIC(5,1),
    particle_count_05um INT,
    particle_count_5um INT,
    differential_pressure_pa NUMERIC(6,2),
    monitored_by INT REFERENCES employee(employee_id),
    within_spec BOOLEAN NOT NULL
);

CREATE TABLE scrap_trend (
    trend_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    product_id INT REFERENCES product(product_id),
    line_id INT REFERENCES production_line(line_id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    total_scrap_qty NUMERIC(14,2),
    total_scrap_cost NUMERIC(14,2),
    scrap_rate_pct NUMERIC(5,2),
    top_reason_id INT REFERENCES scrap_reason(reason_id),
    batch_count INT,
    batches_with_scrap INT
);

CREATE TABLE yield_analysis (
    analysis_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    product_id INT REFERENCES product(product_id),
    line_id INT REFERENCES production_line(line_id),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    avg_yield_pct NUMERIC(5,2),
    min_yield_pct NUMERIC(5,2),
    max_yield_pct NUMERIC(5,2),
    std_dev_yield NUMERIC(5,2),
    batch_count INT,
    target_yield_pct NUMERIC(5,2) DEFAULT 95.0
);

CREATE TABLE oee_record (
    oee_id SERIAL PRIMARY KEY,
    equipment_id INT REFERENCES equipment(equipment_id),
    line_id INT REFERENCES production_line(line_id),
    record_date DATE NOT NULL,
    availability_pct NUMERIC(5,2),
    performance_pct NUMERIC(5,2),
    quality_pct NUMERIC(5,2),
    oee_pct NUMERIC(5,2),             -- availability × performance × quality
    planned_runtime_minutes INT,
    actual_runtime_minutes INT,
    total_units_produced INT,
    good_units_produced INT
);

-- ============================================================
-- SCHEMA: Quality Control (~15 tables)
-- ============================================================

CREATE TABLE qc_sample (
    sample_id SERIAL PRIMARY KEY,
    sample_number VARCHAR(30) NOT NULL,
    batch_id INT REFERENCES batch(batch_id),
    lot_id INT REFERENCES material_lot(lot_id),
    sample_type VARCHAR(50),           -- in_process, finished, stability, retention
    sample_point VARCHAR(100),
    sampled_by INT REFERENCES employee(employee_id),
    sample_date TIMESTAMP NOT NULL,
    quantity NUMERIC(12,2),
    status VARCHAR(20) DEFAULT 'pending'  -- pending, testing, completed, invalid
);

CREATE TABLE qc_test_result (
    result_id SERIAL PRIMARY KEY,
    sample_id INT REFERENCES qc_sample(sample_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    spec_id INT REFERENCES product_specification(spec_id),
    tested_by INT REFERENCES employee(employee_id),
    test_date TIMESTAMP NOT NULL,
    instrument_id INT REFERENCES equipment(equipment_id),
    result_value NUMERIC(12,4),
    result_text VARCHAR(500),
    spec_min NUMERIC(12,4),
    spec_max NUMERIC(12,4),
    passed BOOLEAN NOT NULL,
    reviewed_by INT REFERENCES employee(employee_id),
    review_date TIMESTAMP
);

CREATE TABLE qc_oos_event (
    oos_id SERIAL PRIMARY KEY,
    result_id INT REFERENCES qc_test_result(result_id),
    sample_id INT REFERENCES qc_sample(sample_id),
    batch_id INT REFERENCES batch(batch_id),
    oos_date TIMESTAMP NOT NULL,
    description TEXT,
    phase1_result VARCHAR(20),         -- confirmed, lab_error
    phase2_required BOOLEAN DEFAULT FALSE,
    root_cause TEXT,
    impact_assessment TEXT,
    status VARCHAR(20) DEFAULT 'open',
    closed_by INT REFERENCES employee(employee_id),
    closed_date TIMESTAMP
);

CREATE TABLE stability_study (
    study_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    study_type VARCHAR(50),            -- long_term, accelerated, intermediate
    condition_id INT REFERENCES storage_condition(condition_id),
    start_date DATE NOT NULL,
    planned_duration_months INT,
    status VARCHAR(20) DEFAULT 'active',
    protocol_number VARCHAR(50)
);

CREATE TABLE stability_timepoint (
    timepoint_id SERIAL PRIMARY KEY,
    study_id INT REFERENCES stability_study(study_id),
    months_from_start INT NOT NULL,
    planned_date DATE,
    actual_date DATE,
    status VARCHAR(20) DEFAULT 'pending'
);

CREATE TABLE stability_result (
    result_id SERIAL PRIMARY KEY,
    timepoint_id INT REFERENCES stability_timepoint(timepoint_id),
    test_type_id INT REFERENCES test_type(test_type_id),
    result_value NUMERIC(12,4),
    result_text VARCHAR(200),
    spec_min NUMERIC(12,4),
    spec_max NUMERIC(12,4),
    passed BOOLEAN NOT NULL,
    tested_by INT REFERENCES employee(employee_id),
    test_date TIMESTAMP
);

CREATE TABLE certificate_of_analysis (
    coa_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    lot_id INT REFERENCES material_lot(lot_id),
    coa_number VARCHAR(50) NOT NULL,
    issue_date DATE NOT NULL,
    issued_by INT REFERENCES employee(employee_id),
    approved_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'draft',
    pdf_path VARCHAR(255)
);

CREATE TABLE coa_test_entry (
    entry_id SERIAL PRIMARY KEY,
    coa_id INT REFERENCES certificate_of_analysis(coa_id),
    test_name VARCHAR(100) NOT NULL,
    method VARCHAR(100),
    specification VARCHAR(200),
    result VARCHAR(200),
    passed BOOLEAN NOT NULL
);

-- ============================================================
-- SCHEMA: Deviations & CAPA (~8 tables)
-- ============================================================

CREATE TABLE deviation (
    deviation_id SERIAL PRIMARY KEY,
    deviation_number VARCHAR(30) NOT NULL,
    deviation_type_id INT REFERENCES deviation_type(deviation_type_id),
    batch_id INT REFERENCES batch(batch_id),
    equipment_id INT REFERENCES equipment(equipment_id),
    area_id INT REFERENCES production_area(area_id),
    reported_date TIMESTAMP NOT NULL,
    reported_by INT REFERENCES employee(employee_id),
    description TEXT NOT NULL,
    immediate_action TEXT,
    impact_assessment TEXT,
    root_cause TEXT,
    status VARCHAR(20) DEFAULT 'open',  -- open, investigating, resolved, closed
    closed_date TIMESTAMP,
    closed_by INT REFERENCES employee(employee_id),
    priority_id INT REFERENCES priority_level(priority_id)
);

CREATE TABLE deviation_affected_batch (
    id SERIAL PRIMARY KEY,
    deviation_id INT REFERENCES deviation(deviation_id),
    batch_id INT REFERENCES batch(batch_id),
    impact_description TEXT
);

CREATE TABLE capa (
    capa_id SERIAL PRIMARY KEY,
    capa_number VARCHAR(30) NOT NULL,
    capa_type_id INT REFERENCES capa_type(capa_type_id),
    deviation_id INT REFERENCES deviation(deviation_id),
    oos_id INT REFERENCES qc_oos_event(oos_id),
    opened_date DATE NOT NULL,
    due_date DATE,
    owner_id INT REFERENCES employee(employee_id),
    description TEXT NOT NULL,
    root_cause TEXT,
    proposed_action TEXT,
    actual_action TEXT,
    effectiveness_check TEXT,
    status VARCHAR(20) DEFAULT 'open',  -- open, in_progress, completed, verified, closed
    completed_date DATE,
    verified_by INT REFERENCES employee(employee_id),
    verified_date DATE
);

CREATE TABLE capa_task (
    task_id SERIAL PRIMARY KEY,
    capa_id INT REFERENCES capa(capa_id),
    task_description TEXT NOT NULL,
    assigned_to INT REFERENCES employee(employee_id),
    due_date DATE,
    completed_date DATE,
    status VARCHAR(20) DEFAULT 'open'
);

CREATE TABLE change_control (
    change_id SERIAL PRIMARY KEY,
    change_number VARCHAR(30) NOT NULL,
    change_type VARCHAR(50),           -- process, equipment, material, document
    description TEXT NOT NULL,
    justification TEXT,
    impact_assessment TEXT,
    requested_by INT REFERENCES employee(employee_id),
    requested_date DATE NOT NULL,
    approved_by INT REFERENCES employee(employee_id),
    approved_date DATE,
    implemented_date DATE,
    status VARCHAR(20) DEFAULT 'requested',
    affected_products TEXT,
    regulatory_impact BOOLEAN DEFAULT FALSE
);

CREATE TABLE audit_finding (
    finding_id SERIAL PRIMARY KEY,
    audit_type VARCHAR(50),            -- internal, external, regulatory
    audit_date DATE NOT NULL,
    auditor VARCHAR(100),
    area_id INT REFERENCES production_area(area_id),
    finding_type VARCHAR(50),          -- observation, minor, major, critical
    description TEXT NOT NULL,
    standard_id INT REFERENCES compliance_standard(standard_id),
    response TEXT,
    capa_id INT REFERENCES capa(capa_id),
    status VARCHAR(20) DEFAULT 'open',
    due_date DATE
);

-- ============================================================
-- SCHEMA: Packaging & Distribution (~10 tables)
-- ============================================================

CREATE TABLE packaging_order (
    pkg_order_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    packaging_type_id INT REFERENCES packaging_type(packaging_type_id),
    line_id INT REFERENCES production_line(line_id),
    planned_quantity INT,
    actual_quantity INT,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    status VARCHAR(20) DEFAULT 'planned',
    supervisor_id INT REFERENCES employee(employee_id)
);

CREATE TABLE packaging_material_usage (
    usage_id SERIAL PRIMARY KEY,
    pkg_order_id INT REFERENCES packaging_order(pkg_order_id),
    material_id INT REFERENCES raw_material(material_id),
    lot_id INT REFERENCES material_lot(lot_id),
    quantity_used NUMERIC(12,2),
    quantity_wasted NUMERIC(12,2),
    uom_id INT REFERENCES unit_of_measure(uom_id)
);

CREATE TABLE packaging_defect (
    defect_id SERIAL PRIMARY KEY,
    pkg_order_id INT REFERENCES packaging_order(pkg_order_id),
    defect_type_id INT REFERENCES defect_type(defect_type_id),
    defect_count INT NOT NULL,
    sample_size INT,
    detected_by INT REFERENCES employee(employee_id),
    detected_at TIMESTAMP DEFAULT NOW(),
    action_taken VARCHAR(200)
);

CREATE TABLE finished_goods_inventory (
    inventory_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    product_id INT REFERENCES product(product_id),
    quantity_available INT NOT NULL,
    quantity_reserved INT DEFAULT 0,
    quantity_shipped INT DEFAULT 0,
    warehouse_location VARCHAR(50),
    manufacturing_date DATE,
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'available',  -- available, reserved, shipped, recalled, expired
    last_updated TIMESTAMP DEFAULT NOW()
);

CREATE TABLE customer (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    code VARCHAR(20) NOT NULL,
    country_id INT REFERENCES country(country_id),
    customer_type VARCHAR(50),         -- distributor, hospital, pharmacy, government
    contact_name VARCHAR(100),
    contact_email VARCHAR(100),
    phone VARCHAR(30),
    credit_limit NUMERIC(14,2),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE sales_order (
    order_id SERIAL PRIMARY KEY,
    order_number VARCHAR(30) NOT NULL,
    customer_id INT REFERENCES customer(customer_id),
    order_date DATE NOT NULL,
    required_date DATE,
    ship_date DATE,
    status VARCHAR(20) DEFAULT 'open',
    total_amount NUMERIC(14,2),
    currency_id INT REFERENCES currency(currency_id),
    created_by INT REFERENCES employee(employee_id)
);

CREATE TABLE sales_order_line (
    line_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES sales_order(order_id),
    product_id INT REFERENCES product(product_id),
    quantity_ordered INT NOT NULL,
    unit_price NUMERIC(12,4),
    quantity_shipped INT DEFAULT 0,
    line_total NUMERIC(14,2)
);

CREATE TABLE shipment (
    shipment_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES sales_order(order_id),
    shipment_date TIMESTAMP NOT NULL,
    carrier VARCHAR(100),
    tracking_number VARCHAR(100),
    storage_condition_id INT REFERENCES storage_condition(condition_id),
    shipped_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'in_transit'
);

CREATE TABLE shipment_line (
    shipment_line_id SERIAL PRIMARY KEY,
    shipment_id INT REFERENCES shipment(shipment_id),
    inventory_id INT REFERENCES finished_goods_inventory(inventory_id),
    batch_id INT REFERENCES batch(batch_id),
    quantity_shipped INT NOT NULL
);

CREATE TABLE product_recall (
    recall_id SERIAL PRIMARY KEY,
    product_id INT REFERENCES product(product_id),
    recall_date DATE NOT NULL,
    recall_type VARCHAR(50),           -- voluntary, mandatory
    recall_class VARCHAR(20),          -- Class I, II, III
    reason TEXT NOT NULL,
    affected_batches TEXT,
    affected_quantity INT,
    initiated_by INT REFERENCES employee(employee_id),
    status VARCHAR(20) DEFAULT 'active',
    completion_date DATE
);

-- ============================================================
-- SCHEMA: Documents & Compliance (~8 tables)
-- ============================================================

CREATE TABLE document (
    document_id SERIAL PRIMARY KEY,
    doc_number VARCHAR(50) NOT NULL,
    doc_type_id INT REFERENCES document_type(doc_type_id),
    title VARCHAR(200) NOT NULL,
    version INT DEFAULT 1,
    status_id INT REFERENCES approval_status(status_id),
    author_id INT REFERENCES employee(employee_id),
    created_date DATE NOT NULL,
    effective_date DATE,
    review_date DATE,
    expiry_date DATE,
    department_id INT REFERENCES department(department_id),
    file_path VARCHAR(255)
);

CREATE TABLE document_revision (
    revision_id SERIAL PRIMARY KEY,
    document_id INT REFERENCES document(document_id),
    version INT NOT NULL,
    revision_date DATE NOT NULL,
    revised_by INT REFERENCES employee(employee_id),
    change_description TEXT,
    approved_by INT REFERENCES employee(employee_id),
    approved_date DATE
);

CREATE TABLE document_training (
    training_id SERIAL PRIMARY KEY,
    document_id INT REFERENCES document(document_id),
    employee_id INT REFERENCES employee(employee_id),
    assigned_date DATE NOT NULL,
    completed_date DATE,
    status VARCHAR(20) DEFAULT 'pending',
    score NUMERIC(5,2)
);

CREATE TABLE batch_record_entry (
    entry_id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES batch(batch_id),
    document_id INT REFERENCES document(document_id),
    entry_date TIMESTAMP DEFAULT NOW(),
    entered_by INT REFERENCES employee(employee_id),
    section VARCHAR(100),
    field_name VARCHAR(100),
    field_value TEXT,
    verified_by INT REFERENCES employee(employee_id),
    verified_date TIMESTAMP
);

CREATE TABLE electronic_signature (
    signature_id SERIAL PRIMARY KEY,
    signer_id INT REFERENCES employee(employee_id),
    sign_date TIMESTAMP NOT NULL,
    sign_meaning VARCHAR(100),         -- authored, reviewed, approved, verified
    document_id INT REFERENCES document(document_id),
    batch_id INT REFERENCES batch(batch_id),
    record_type VARCHAR(50),
    record_id INT,
    ip_address VARCHAR(45)
);

CREATE TABLE audit_trail (
    trail_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id INT NOT NULL,
    action VARCHAR(20) NOT NULL,       -- INSERT, UPDATE, DELETE
    changed_by INT REFERENCES employee(employee_id),
    changed_at TIMESTAMP DEFAULT NOW(),
    old_values JSONB,
    new_values JSONB,
    reason TEXT
);

CREATE TABLE training_record (
    record_id SERIAL PRIMARY KEY,
    employee_id INT REFERENCES employee(employee_id),
    training_type_id INT REFERENCES training_type(training_type_id),
    training_date DATE NOT NULL,
    trainer_id INT REFERENCES employee(employee_id),
    duration_hours NUMERIC(4,1),
    score NUMERIC(5,2),
    passed BOOLEAN,
    certificate_number VARCHAR(50),
    expiry_date DATE
);

CREATE TABLE complaint (
    complaint_id SERIAL PRIMARY KEY,
    complaint_number VARCHAR(30) NOT NULL,
    product_id INT REFERENCES product(product_id),
    batch_id INT REFERENCES batch(batch_id),
    customer_id INT REFERENCES customer(customer_id),
    received_date DATE NOT NULL,
    complaint_type VARCHAR(50),        -- quality, adverse_event, packaging, labeling
    severity VARCHAR(20),
    description TEXT NOT NULL,
    investigation TEXT,
    root_cause TEXT,
    capa_id INT REFERENCES capa(capa_id),
    status VARCHAR(20) DEFAULT 'open',
    closed_date DATE,
    reportable BOOLEAN DEFAULT FALSE
);

-- ============================================================
-- SCHEMA: Energy & Utilities (~5 tables)
-- ============================================================

CREATE TABLE utility_type (
    utility_type_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,         -- electricity, water, steam, compressed_air, nitrogen
    unit VARCHAR(20) NOT NULL
);

CREATE TABLE utility_consumption (
    consumption_id SERIAL PRIMARY KEY,
    utility_type_id INT REFERENCES utility_type(utility_type_id),
    area_id INT REFERENCES production_area(area_id),
    reading_date DATE NOT NULL,
    consumption_value NUMERIC(14,2) NOT NULL,
    cost NUMERIC(12,2),
    batch_id INT REFERENCES batch(batch_id)
);

CREATE TABLE energy_target (
    target_id SERIAL PRIMARY KEY,
    site_id INT REFERENCES site(site_id),
    utility_type_id INT REFERENCES utility_type(utility_type_id),
    target_year INT NOT NULL,
    monthly_target NUMERIC(14,2),
    annual_target NUMERIC(14,2)
);

-- ============================================================
-- INDEXES for performance
-- ============================================================

CREATE INDEX idx_batch_product ON batch(product_id);
CREATE INDEX idx_batch_site ON batch(site_id);
CREATE INDEX idx_batch_status ON batch(status);
CREATE INDEX idx_batch_start_date ON batch(start_date);
CREATE INDEX idx_scrap_batch ON scrap_event(batch_id);
CREATE INDEX idx_scrap_reason ON scrap_event(reason_id);
CREATE INDEX idx_scrap_date ON scrap_event(scrap_date);
CREATE INDEX idx_material_lot_material ON material_lot(material_id);
CREATE INDEX idx_material_lot_status ON material_lot(status);
CREATE INDEX idx_qc_result_sample ON qc_test_result(sample_id);
CREATE INDEX idx_qc_result_passed ON qc_test_result(passed);
CREATE INDEX idx_deviation_batch ON deviation(batch_id);
CREATE INDEX idx_deviation_status ON deviation(status);
CREATE INDEX idx_equipment_downtime_equip ON equipment_downtime(equipment_id);
CREATE INDEX idx_batch_yield_batch ON batch_yield(batch_id);
CREATE INDEX idx_packaging_defect_order ON packaging_defect(pkg_order_id);
CREATE INDEX idx_fg_inventory_product ON finished_goods_inventory(product_id);
CREATE INDEX idx_batch_cost_batch ON batch_cost(batch_id);
CREATE INDEX idx_complaint_product ON complaint(product_id);


-- ============================================================
-- SAMPLE DATA
-- ============================================================

-- Countries
INSERT INTO country (code, name, region) VALUES
('US', 'United States', 'North America'),
('IN', 'India', 'South Asia'),
('DE', 'Germany', 'Europe'),
('JP', 'Japan', 'East Asia'),
('BR', 'Brazil', 'South America'),
('GB', 'United Kingdom', 'Europe'),
('CN', 'China', 'East Asia'),
('CH', 'Switzerland', 'Europe');

-- Currencies
INSERT INTO currency (code, name, exchange_rate_to_usd) VALUES
('USD', 'US Dollar', 1.0),
('EUR', 'Euro', 0.92),
('INR', 'Indian Rupee', 83.5),
('JPY', 'Japanese Yen', 150.0),
('GBP', 'British Pound', 0.79);

-- Regulatory Bodies
INSERT INTO regulatory_body (name, country_id, website) VALUES
('FDA', 1, 'https://www.fda.gov'),
('EMA', 3, 'https://www.ema.europa.eu'),
('CDSCO', 2, 'https://cdsco.gov.in'),
('PMDA', 4, 'https://www.pmda.go.jp');

-- Compliance Standards
INSERT INTO compliance_standard (code, name, body_id, effective_date) VALUES
('21CFR211', 'Current Good Manufacturing Practice', 1, '2020-01-01'),
('ICH-Q7', 'Good Manufacturing Practice for APIs', 1, '2019-06-01'),
('EU-GMP', 'EU Guidelines for Good Manufacturing Practice', 2, '2021-01-01'),
('ISO-13485', 'Medical Devices Quality Management', NULL, '2016-03-01');

-- Shift Types
INSERT INTO shift_type (name, start_time, end_time) VALUES
('Morning', '06:00', '14:00'),
('Afternoon', '14:00', '22:00'),
('Night', '22:00', '06:00');

-- Unit of Measure
INSERT INTO unit_of_measure (code, name, uom_type) VALUES
('kg', 'Kilogram', 'weight'),
('g', 'Gram', 'weight'),
('mg', 'Milligram', 'weight'),
('L', 'Liter', 'volume'),
('mL', 'Milliliter', 'volume'),
('unit', 'Unit', 'count'),
('tablet', 'Tablet', 'count'),
('capsule', 'Capsule', 'count');

-- Dosage Forms
INSERT INTO dosage_form (name, description) VALUES
('Tablet', 'Solid oral dosage form'),
('Capsule', 'Gelatin shell containing drug'),
('Injectable', 'Sterile solution for injection'),
('Syrup', 'Liquid oral dosage form'),
('Cream', 'Topical semi-solid preparation'),
('Ointment', 'Topical greasy preparation');

-- Product Categories
INSERT INTO product_category (name, description) VALUES
('Analgesic', 'Pain relief medications'),
('Antibiotic', 'Anti-bacterial medications'),
('Cardiovascular', 'Heart and blood vessel medications'),
('Antidiabetic', 'Blood sugar management'),
('Respiratory', 'Lung and airway medications'),
('Gastrointestinal', 'Digestive system medications'),
('Dermatological', 'Skin treatment medications'),
('Oncology', 'Cancer treatment medications');

-- Equipment Types
INSERT INTO equipment_type (name, category, description) VALUES
('Rapid Mixer Granulator', 'processing', 'High-shear wet granulation'),
('Fluid Bed Dryer', 'processing', 'Drying granules with hot air'),
('Tablet Press', 'processing', 'Compression of powder into tablets'),
('Coating Machine', 'processing', 'Film or sugar coating of tablets'),
('Blister Packing', 'packaging', 'Blister strip packaging'),
('Bottle Filling', 'packaging', 'Liquid/solid bottle filling'),
('HPLC', 'testing', 'High Performance Liquid Chromatography'),
('Dissolution Tester', 'testing', 'Drug release rate testing'),
('Hardness Tester', 'testing', 'Tablet hardness measurement'),
('Friability Tester', 'testing', 'Tablet friability testing'),
('Capsule Filler', 'processing', 'Automatic capsule filling'),
('V-Blender', 'processing', 'Powder blending'),
('Autoclave', 'processing', 'Steam sterilization'),
('Lyophilizer', 'processing', 'Freeze drying');

-- Defect Types
INSERT INTO defect_type (code, name, severity, description) VALUES
('CAP', 'Capping', 'major', 'Tablet splits into layers'),
('CHIP', 'Chipping', 'minor', 'Small pieces break from tablet edge'),
('WVAR', 'Weight Variation', 'major', 'Tablet weight outside specification'),
('DISC', 'Discoloration', 'major', 'Color change from specification'),
('HARD', 'Low Hardness', 'minor', 'Tablet too soft'),
('FRIA', 'High Friability', 'major', 'Excessive tablet erosion'),
('SEAL', 'Seal Defect', 'critical', 'Blister pack seal failure'),
('LABEL', 'Labeling Error', 'critical', 'Wrong or missing label'),
('CRACK', 'Cracking', 'major', 'Visible cracks on tablet surface'),
('STICK', 'Sticking', 'minor', 'Tablet sticks to punch face');

-- Scrap Reasons
INSERT INTO scrap_reason (code, name, category, description) VALUES
('MAT-001', 'Raw Material OOS', 'material', 'Raw material failed quality test'),
('MAT-002', 'Material Expired', 'material', 'Material past expiry date'),
('MAT-003', 'Wrong Material Dispensed', 'material', 'Incorrect material used'),
('EQP-001', 'Equipment Breakdown', 'equipment', 'Unexpected equipment failure'),
('EQP-002', 'Calibration Drift', 'equipment', 'Equipment out of calibration'),
('EQP-003', 'Tooling Wear', 'equipment', 'Worn punches or dies'),
('PRC-001', 'Process Deviation', 'process', 'Out-of-spec process parameter'),
('PRC-002', 'Over-granulation', 'process', 'Excessive granulation time'),
('PRC-003', 'Under-drying', 'process', 'Insufficient drying moisture too high'),
('HUM-001', 'Operator Error', 'human', 'Human mistake during processing'),
('HUM-002', 'Documentation Error', 'human', 'Batch record discrepancy'),
('ENV-001', 'Temperature Excursion', 'environmental', 'Room temp out of range'),
('ENV-002', 'Humidity Excursion', 'environmental', 'Humidity out of specification'),
('ENV-003', 'Contamination', 'environmental', 'Cross-contamination detected');

-- Test Types
INSERT INTO test_type (code, name, category, description) VALUES
('DISS', 'Dissolution', 'chemical', 'Drug release rate in dissolution medium'),
('HARD', 'Hardness', 'physical', 'Breaking force of tablet'),
('FRIA', 'Friability', 'physical', 'Percentage weight loss after tumbling'),
('WVAR', 'Weight Variation', 'physical', 'Individual tablet weight variation'),
('ASSAY', 'Assay', 'chemical', 'Active ingredient content determination'),
('MICRO', 'Microbial Limit', 'microbiological', 'Total microbial count'),
('MOIST', 'Moisture Content', 'physical', 'Water content by LOD'),
('THICK', 'Thickness', 'physical', 'Tablet thickness measurement'),
('DISINT', 'Disintegration', 'physical', 'Time to disintegrate in medium'),
('IMPURITY', 'Related Substances', 'chemical', 'Impurity profiling by HPLC'),
('STERILITY', 'Sterility Test', 'microbiological', 'Absence of viable organisms'),
('ENDOTOXIN', 'Bacterial Endotoxin', 'microbiological', 'LAL test for pyrogens');

-- Waste Categories
INSERT INTO waste_category (name, disposal_method, regulatory_code) VALUES
('Hazardous Chemical', 'Incineration', 'RCRA-D001'),
('Non-Hazardous Solid', 'Landfill', 'SW-NH'),
('Recyclable Material', 'Recycling', 'RC-001'),
('Pharmaceutical Waste', 'High-Temp Incineration', 'RCRA-P/U'),
('Biological Waste', 'Autoclave + Incineration', 'BIO-001');

-- Storage Conditions
INSERT INTO storage_condition (name, min_temp_c, max_temp_c, min_humidity_pct, max_humidity_pct) VALUES
('Room Temperature', 15.0, 25.0, 30.0, 65.0),
('Cold Chain', 2.0, 8.0, NULL, NULL),
('Frozen', -25.0, -15.0, NULL, NULL),
('Controlled Room Temp', 20.0, 25.0, 40.0, 60.0),
('Below 30C', 15.0, 30.0, NULL, 75.0);

-- Packaging Types
INSERT INTO packaging_type (name, material, description) VALUES
('Alu-Alu Blister', 'Aluminum', 'Cold-formed aluminum blister'),
('PVC Blister', 'PVC/Aluminum', 'Thermoformed PVC with alu lid'),
('HDPE Bottle', 'HDPE Plastic', 'High-density polyethylene bottle'),
('Glass Vial', 'Borosilicate Glass', 'Type I glass vial for injectables'),
('Ampoule', 'Glass', 'Sealed glass ampoule'),
('Sachet', 'Foil Laminate', 'Single-dose foil sachet'),
('Strip Pack', 'Aluminum Foil', 'Aluminum strip packaging');

-- Deviation Types
INSERT INTO deviation_type (code, name, severity, requires_capa) VALUES
('PD', 'Process Deviation', 'major', TRUE),
('ED', 'Equipment Deviation', 'major', TRUE),
('MD', 'Material Deviation', 'major', TRUE),
('ENV', 'Environmental Deviation', 'minor', FALSE),
('DOC', 'Documentation Deviation', 'minor', FALSE),
('CRIT', 'Critical Deviation', 'critical', TRUE);

-- CAPA Types
INSERT INTO capa_type (name, description) VALUES
('Corrective', 'Action to eliminate the cause of a detected nonconformity'),
('Preventive', 'Action to eliminate the cause of a potential nonconformity');

-- Document Types
INSERT INTO document_type (name, retention_years) VALUES
('Standard Operating Procedure', 10),
('Batch Manufacturing Record', 7),
('Certificate of Analysis', 7),
('Deviation Report', 10),
('CAPA Report', 10),
('Validation Protocol', 10),
('Stability Report', 15),
('Change Control Record', 10),
('Training Record', 7);

-- Approval Statuses
INSERT INTO approval_status (name) VALUES
('Draft'), ('Pending Review'), ('Approved'), ('Rejected'), ('Superseded');

-- Material Classes
INSERT INTO material_class (name, description, requires_coa) VALUES
('Active Pharmaceutical Ingredient', 'API - the active drug substance', TRUE),
('Excipient', 'Inactive ingredient used in formulation', TRUE),
('Solvent', 'Liquid used in processing', TRUE),
('Packaging Material', 'Primary and secondary packaging', FALSE),
('Cleaning Agent', 'Equipment cleaning chemicals', FALSE);

-- Allergens
INSERT INTO allergen (name, description) VALUES
('Lactose', 'Milk sugar - common tablet filler'),
('Gluten', 'Wheat protein - starch source'),
('Gelatin', 'Animal-derived capsule shell'),
('Soy Lecithin', 'Soybean-derived emulsifier'),
('Corn Starch', 'Corn-derived binder/filler');

-- Environmental Zones
INSERT INTO environmental_zone (name, max_particles_05um, max_particles_5um, description) VALUES
('Grade A', 3520, 20, 'High-risk operations, aseptic filling'),
('Grade B', 3520, 29, 'Background for Grade A zone'),
('Grade C', 352000, 2900, 'Less critical manufacturing steps'),
('Grade D', 3520000, 29000, 'Least critical clean area'),
('Unclassified', NULL, NULL, 'General manufacturing area');

-- Maintenance Types
INSERT INTO maintenance_type (name, frequency_days, description) VALUES
('Preventive Maintenance', 90, 'Scheduled maintenance per plan'),
('Corrective Maintenance', NULL, 'Repair after failure'),
('Calibration', 180, 'Instrument calibration'),
('Qualification', 365, 'Equipment qualification/requalification');

-- Training Types
INSERT INTO training_type (name, required_for, validity_months) VALUES
('GMP Basics', 'All employees', 12),
('Clean Room Behavior', 'Production operators', 12),
('HPLC Operation', 'QC analysts', 24),
('Batch Record Documentation', 'Production operators', 12),
('Deviation Handling', 'Supervisors', 12),
('Safety & Emergency', 'All employees', 12),
('Aseptic Technique', 'Sterile operators', 6);

-- Cost Centers
INSERT INTO cost_center (code, name, department) VALUES
('CC-MFG', 'Manufacturing', 'Production'),
('CC-QC', 'Quality Control', 'Quality'),
('CC-QA', 'Quality Assurance', 'Quality'),
('CC-WH', 'Warehouse', 'Supply Chain'),
('CC-ENG', 'Engineering', 'Engineering'),
('CC-RD', 'R&D', 'Research'),
('CC-PKG', 'Packaging', 'Production');

-- Priority Levels
INSERT INTO priority_level (name, sla_hours) VALUES
('Low', 168),
('Medium', 72),
('High', 24),
('Critical', 4);

-- Utility Types
INSERT INTO utility_type (name, unit) VALUES
('Electricity', 'kWh'),
('Water (Purified)', 'Liters'),
('Steam', 'kg'),
('Compressed Air', 'm³'),
('Nitrogen', 'm³'),
('Chilled Water', 'Liters');

-- Specification Types
INSERT INTO specification_type (name, description) VALUES
('Raw Material', 'Incoming material specifications'),
('In-Process', 'During manufacturing checks'),
('Finished Product', 'Final release specifications'),
('Stability', 'Stability study specifications');

-- ============================================================
-- OPERATIONAL DATA: Sites, Buildings, Areas, Lines
-- ============================================================

INSERT INTO site (name, code, country_id, address, gmp_certified, max_capacity_units_per_day) VALUES
('PharmaCorp US Plant', 'US-01', 1, '1200 Pharma Way, New Jersey, NJ', TRUE, 5000000),
('PharmaCorp India Plant', 'IN-01', 2, 'Plot 42, Pharma SEZ, Hyderabad', TRUE, 8000000),
('PharmaCorp Germany Plant', 'DE-01', 3, 'Pharmastrasse 15, Frankfurt', TRUE, 3000000);

INSERT INTO building (site_id, name, zone_id, floor_area_sqm) VALUES
(1, 'Solid Dosage Block A', 4, 5000),
(1, 'Solid Dosage Block B', 4, 3000),
(1, 'Injectable Block', 1, 2000),
(1, 'QC Laboratory', 5, 1500),
(1, 'Warehouse', 5, 4000),
(2, 'Oral Solid Dosage', 4, 8000),
(2, 'Liquid & Semi-solid', 4, 3000),
(2, 'QC Laboratory', 5, 2000),
(2, 'Warehouse', 5, 6000),
(3, 'Sterile Manufacturing', 1, 4000),
(3, 'QC Laboratory', 5, 1000);

INSERT INTO production_area (building_id, name, zone_id, area_type, max_concurrent_batches) VALUES
(1, 'Dispensing Room A1', 4, 'manufacturing', 1),
(1, 'Granulation Suite A2', 4, 'manufacturing', 2),
(1, 'Compression Hall A3', 4, 'manufacturing', 4),
(1, 'Coating Room A4', 4, 'manufacturing', 2),
(2, 'Packaging Hall B1', 5, 'packaging', 3),
(3, 'Aseptic Fill Room', 1, 'manufacturing', 1),
(6, 'OSD Dispensing', 4, 'manufacturing', 2),
(6, 'OSD Granulation', 4, 'manufacturing', 3),
(6, 'OSD Compression', 4, 'manufacturing', 6),
(6, 'OSD Coating', 4, 'manufacturing', 2),
(6, 'OSD Packaging', 5, 'packaging', 4),
(10, 'Sterile Dispensing', 2, 'manufacturing', 1),
(10, 'Sterile Fill-Finish', 1, 'manufacturing', 1);

INSERT INTO department (site_id, name, cost_center_id) VALUES
(1, 'Production US', 1),
(1, 'Quality Control US', 2),
(1, 'Quality Assurance US', 3),
(1, 'Warehouse US', 4),
(1, 'Engineering US', 5),
(2, 'Production India', 1),
(2, 'Quality Control India', 2),
(2, 'Quality Assurance India', 3),
(2, 'Warehouse India', 4),
(3, 'Production Germany', 1),
(3, 'Quality Control Germany', 2);

INSERT INTO production_line (area_id, name, line_type, max_speed_units_per_hour, status) VALUES
(3, 'Tablet Line 1', 'tablet', 250000, 'active'),
(3, 'Tablet Line 2', 'tablet', 200000, 'active'),
(3, 'Tablet Line 3', 'tablet', 180000, 'active'),
(5, 'Blister Pack Line 1', 'tablet', 150000, 'active'),
(5, 'Bottle Line 1', 'tablet', 50000, 'active'),
(6, 'Injectable Line 1', 'injectable', 20000, 'active'),
(9, 'India Tablet Line 1', 'tablet', 300000, 'active'),
(9, 'India Tablet Line 2', 'tablet', 300000, 'active'),
(9, 'India Capsule Line 1', 'capsule', 200000, 'active'),
(11, 'India Blister Line 1', 'tablet', 200000, 'active'),
(11, 'India Bottle Line 1', 'tablet', 80000, 'active'),
(13, 'Germany Injectable Line 1', 'injectable', 15000, 'active');

INSERT INTO work_center (line_id, name, process_step, sequence_order) VALUES
(1, 'TL1 Dispensing', 'dispensing', 1),
(1, 'TL1 Granulation', 'granulation', 2),
(1, 'TL1 Drying', 'drying', 3),
(1, 'TL1 Blending', 'blending', 4),
(1, 'TL1 Compression', 'compression', 5),
(1, 'TL1 Coating', 'coating', 6),
(2, 'TL2 Dispensing', 'dispensing', 1),
(2, 'TL2 Granulation', 'granulation', 2),
(2, 'TL2 Compression', 'compression', 3),
(7, 'India TL1 Dispensing', 'dispensing', 1),
(7, 'India TL1 Granulation', 'granulation', 2),
(7, 'India TL1 Compression', 'compression', 3),
(7, 'India TL1 Coating', 'coating', 4);

-- ============================================================
-- EMPLOYEES
-- ============================================================

INSERT INTO employee (employee_code, first_name, last_name, department_id, site_id, job_title, hire_date, is_active, email) VALUES
('EMP001', 'John', 'Anderson', 1, 1, 'Production Manager', '2018-03-15', TRUE, 'j.anderson@pharmacorp.com'),
('EMP002', 'Sarah', 'Mitchell', 2, 1, 'QC Manager', '2019-06-01', TRUE, 's.mitchell@pharmacorp.com'),
('EMP003', 'Mike', 'Thompson', 1, 1, 'Senior Operator', '2020-01-10', TRUE, 'm.thompson@pharmacorp.com'),
('EMP004', 'Lisa', 'Chen', 1, 1, 'Operator', '2021-04-20', TRUE, 'l.chen@pharmacorp.com'),
('EMP005', 'David', 'Kumar', 6, 2, 'Production Manager India', '2017-08-01', TRUE, 'd.kumar@pharmacorp.com'),
('EMP006', 'Priya', 'Sharma', 7, 2, 'QC Analyst India', '2020-11-15', TRUE, 'p.sharma@pharmacorp.com'),
('EMP007', 'James', 'Wilson', 3, 1, 'QA Director', '2016-02-28', TRUE, 'j.wilson@pharmacorp.com'),
('EMP008', 'Maria', 'Garcia', 5, 1, 'Maintenance Engineer', '2019-09-01', TRUE, 'm.garcia@pharmacorp.com'),
('EMP009', 'Raj', 'Patel', 6, 2, 'Senior Operator India', '2019-03-15', TRUE, 'r.patel@pharmacorp.com'),
('EMP010', 'Hans', 'Mueller', 10, 3, 'Production Manager Germany', '2018-07-01', TRUE, 'h.mueller@pharmacorp.com'),
('EMP011', 'Anna', 'Schmidt', 11, 3, 'QC Analyst Germany', '2021-01-15', TRUE, 'a.schmidt@pharmacorp.com'),
('EMP012', 'Robert', 'Brown', 4, 1, 'Warehouse Supervisor', '2020-06-01', TRUE, 'r.brown@pharmacorp.com'),
('EMP013', 'Deepa', 'Nair', 8, 2, 'QA Manager India', '2018-05-10', TRUE, 'd.nair@pharmacorp.com'),
('EMP014', 'Tom', 'Harris', 1, 1, 'Operator', '2022-03-01', TRUE, 't.harris@pharmacorp.com'),
('EMP015', 'Arun', 'Reddy', 6, 2, 'Operator India', '2022-08-20', TRUE, 'a.reddy@pharmacorp.com');

-- ============================================================
-- SUPPLIERS & MATERIALS
-- ============================================================

INSERT INTO supplier (name, code, country_id, contact_name, contact_email, is_approved, approval_date, rating, gmp_certified) VALUES
('ChemSource Inc', 'SUP-001', 1, 'Mark Stevens', 'mark@chemsource.com', TRUE, '2022-01-15', 4.5, TRUE),
('IndoPharma Chemicals', 'SUP-002', 2, 'Vikram Singh', 'vikram@indopharma.in', TRUE, '2021-06-01', 4.2, TRUE),
('EuroChem GmbH', 'SUP-003', 3, 'Klaus Weber', 'klaus@eurochem.de', TRUE, '2021-09-01', 4.8, TRUE),
('Pacific Excipients', 'SUP-004', 7, 'Wei Zhang', 'wei@pacificex.cn', TRUE, '2022-03-01', 3.9, TRUE),
('GlobalPack Solutions', 'SUP-005', 1, 'Jennifer Lee', 'jennifer@globalpack.com', TRUE, '2020-12-01', 4.3, FALSE),
('BioSynth Labs', 'SUP-006', 2, 'Amit Joshi', 'amit@biosynth.in', TRUE, '2023-01-15', 4.0, TRUE),
('AlpinePharma AG', 'SUP-007', 8, 'Thomas Bauer', 'thomas@alpinepharma.ch', TRUE, '2022-06-01', 4.7, TRUE);

INSERT INTO raw_material (code, name, class_id, uom_id, storage_condition_id, shelf_life_months, reorder_point, safety_stock, is_controlled, cas_number) VALUES
('RM-001', 'Paracetamol (Acetaminophen)', 1, 1, 1, 36, 500, 200, FALSE, '103-90-2'),
('RM-002', 'Amoxicillin Trihydrate', 1, 1, 1, 24, 300, 100, FALSE, '61336-70-7'),
('RM-003', 'Metformin HCl', 1, 1, 1, 36, 400, 150, FALSE, '1115-70-4'),
('RM-004', 'Atorvastatin Calcium', 1, 1, 4, 24, 100, 50, FALSE, '134523-03-8'),
('RM-005', 'Omeprazole', 1, 1, 4, 18, 80, 30, FALSE, '73590-58-6'),
('RM-006', 'Microcrystalline Cellulose', 2, 1, 1, 60, 1000, 500, FALSE, '9004-34-6'),
('RM-007', 'Lactose Monohydrate', 2, 1, 1, 60, 800, 400, FALSE, '5989-81-1'),
('RM-008', 'Croscarmellose Sodium', 2, 1, 1, 48, 200, 100, FALSE, '74811-65-7'),
('RM-009', 'Magnesium Stearate', 2, 1, 1, 60, 100, 50, FALSE, '557-04-0'),
('RM-010', 'Povidone K30', 2, 1, 1, 48, 150, 80, FALSE, '9003-39-8'),
('RM-011', 'Hydroxypropyl Methylcellulose', 2, 1, 1, 60, 200, 100, FALSE, '9004-65-3'),
('RM-012', 'Talc', 2, 1, 1, 60, 300, 150, FALSE, '14807-96-6'),
('RM-013', 'Colloidal Silicon Dioxide', 2, 1, 1, 60, 50, 20, FALSE, '7631-86-9'),
('RM-014', 'Starch (Maize)', 2, 1, 1, 48, 500, 200, FALSE, '9005-25-8'),
('RM-015', 'Titanium Dioxide', 2, 1, 1, 60, 50, 20, FALSE, '13463-67-7'),
('RM-016', 'Purified Water', 3, 4, 1, NULL, NULL, NULL, FALSE, '7732-18-5'),
('RM-017', 'Isopropyl Alcohol', 3, 4, 1, 36, 200, 100, FALSE, '67-63-0'),
('RM-018', 'Alu-Alu Foil Roll', 4, 6, 1, NULL, 5000, 2000, FALSE, NULL),
('RM-019', 'PVC Foil Roll', 4, 6, 1, NULL, 5000, 2000, FALSE, NULL),
('RM-020', 'HDPE Bottles 100ct', 4, 6, 1, NULL, 10000, 5000, FALSE, NULL);

-- Material-Allergen mapping
INSERT INTO material_allergen (material_id, allergen_id) VALUES
(7, 1),   -- Lactose contains Lactose allergen
(14, 5);  -- Maize Starch contains Corn allergen

-- Supplier-Material relationships
INSERT INTO supplier_material (supplier_id, material_id, supplier_part_number, lead_time_days, min_order_qty, unit_price, currency_id, is_primary, qualification_date) VALUES
(1, 1, 'CS-APAP-001', 14, 100, 25.50, 1, TRUE, '2022-01-15'),
(2, 1, 'IP-APAP-001', 21, 200, 18.00, 3, FALSE, '2022-03-01'),
(3, 2, 'EC-AMOX-001', 21, 50, 85.00, 2, TRUE, '2021-09-01'),
(6, 3, 'BS-MET-001', 18, 100, 15.00, 3, TRUE, '2023-01-15'),
(7, 4, 'AP-ATOR-001', 28, 25, 250.00, 1, TRUE, '2022-06-01'),
(1, 6, 'CS-MCC-001', 10, 500, 8.50, 1, TRUE, '2022-01-15'),
(4, 7, 'PE-LAC-001', 25, 500, 5.00, 1, TRUE, '2022-03-01'),
(1, 8, 'CS-CCS-001', 10, 100, 22.00, 1, TRUE, '2022-01-15'),
(1, 9, 'CS-MGS-001', 10, 50, 12.00, 1, TRUE, '2022-01-15'),
(5, 18, 'GP-ALU-001', 7, 1000, 0.85, 1, TRUE, '2020-12-01'),
(5, 19, 'GP-PVC-001', 7, 1000, 0.45, 1, TRUE, '2020-12-01'),
(5, 20, 'GP-BOT-001', 7, 5000, 0.25, 1, TRUE, '2020-12-01');

-- ============================================================
-- PRODUCTS & FORMULATIONS
-- ============================================================

INSERT INTO product (code, name, category_id, dosage_form_id, strength, shelf_life_months, storage_condition_id, status, launch_date) VALUES
('PRD-001', 'Paracetamol 500mg Tablets', 1, 1, '500mg', 36, 1, 'active', '2020-01-01'),
('PRD-002', 'Amoxicillin 500mg Capsules', 2, 2, '500mg', 24, 1, 'active', '2020-06-01'),
('PRD-003', 'Metformin 500mg Tablets', 4, 1, '500mg', 36, 1, 'active', '2021-01-01'),
('PRD-004', 'Metformin 1000mg Tablets', 4, 1, '1000mg', 36, 1, 'active', '2021-06-01'),
('PRD-005', 'Atorvastatin 10mg Tablets', 3, 1, '10mg', 24, 4, 'active', '2022-01-01'),
('PRD-006', 'Atorvastatin 20mg Tablets', 3, 1, '20mg', 24, 4, 'active', '2022-01-01'),
('PRD-007', 'Omeprazole 20mg Capsules', 6, 2, '20mg', 24, 4, 'active', '2022-06-01'),
('PRD-008', 'Paracetamol 650mg Tablets', 1, 1, '650mg', 36, 1, 'active', '2023-01-01');

-- BOMs
INSERT INTO bill_of_materials (product_id, version, effective_date, status, approved_by, batch_size, batch_size_uom_id) VALUES
(1, 1, '2020-01-01', 'active', 7, 500, 1),    -- 500 kg batch of Paracetamol 500mg
(2, 1, '2020-06-01', 'active', 7, 200, 1),    -- 200 kg batch of Amoxicillin
(3, 1, '2021-01-01', 'active', 7, 600, 1),    -- 600 kg batch of Metformin 500mg
(5, 1, '2022-01-01', 'active', 7, 100, 1);    -- 100 kg batch of Atorvastatin

-- BOM Lines for Paracetamol 500mg
INSERT INTO bom_line (bom_id, material_id, quantity_per_batch, uom_id, overage_pct, is_active_ingredient, sequence_order) VALUES
(1, 1, 350.00, 1, 2.0, TRUE, 1),     -- Paracetamol API 350kg
(1, 6, 80.00, 1, 1.0, FALSE, 2),     -- MCC 80kg
(1, 7, 40.00, 1, 1.0, FALSE, 3),     -- Lactose 40kg
(1, 14, 15.00, 1, 1.0, FALSE, 4),    -- Starch 15kg
(1, 8, 8.00, 1, 0.5, FALSE, 5),      -- Croscarmellose 8kg
(1, 10, 5.00, 1, 0.5, FALSE, 6),     -- Povidone 5kg
(1, 9, 1.50, 1, 0.5, FALSE, 7),      -- Mag Stearate 1.5kg
(1, 13, 0.50, 1, 0.5, FALSE, 8);     -- Colloidal SiO2 0.5kg

-- Master Batch Record for Paracetamol
INSERT INTO master_batch_record (product_id, version, bom_id, effective_date, status_id, approved_by, total_process_steps, expected_yield_pct, document_number) VALUES
(1, 1, 1, '2020-01-01', 3, 7, 7, 97.0, 'MBR-PRD001-V1'),
(3, 1, 3, '2021-01-01', 3, 7, 7, 96.0, 'MBR-PRD003-V1');

-- Process Steps for Paracetamol
INSERT INTO process_step (mbr_id, step_number, name, description, work_center_id, expected_duration_minutes, critical_step) VALUES
(1, 1, 'Dispensing', 'Weigh and dispense all raw materials per BOM', 1, 60, TRUE),
(1, 2, 'Dry Mixing', 'Blend API with fillers in V-Blender', 4, 20, FALSE),
(1, 3, 'Wet Granulation', 'Add binder solution and granulate in RMG', 2, 30, TRUE),
(1, 4, 'Drying', 'Dry granules in FBD to target LOD', 3, 45, TRUE),
(1, 5, 'Blending', 'Final blend with lubricant and glidant', 4, 15, FALSE),
(1, 6, 'Compression', 'Compress into tablets on rotary press', 5, 120, TRUE),
(1, 7, 'Coating', 'Film coat tablets', 6, 90, FALSE);

-- Process Parameters
INSERT INTO process_parameter (step_id, name, target_value, min_value, max_value, uom_id, is_critical) VALUES
(3, 'Impeller Speed', 250, 200, 300, 6, TRUE),
(3, 'Chopper Speed', 1500, 1200, 1800, 6, TRUE),
(3, 'Granulation Time', 8, 5, 12, 6, TRUE),
(4, 'Inlet Temperature', 60, 55, 65, 6, TRUE),
(4, 'LOD Target', 2.0, 1.0, 3.0, 6, TRUE),
(6, 'Compression Force', 15, 10, 20, 6, TRUE),
(6, 'Turret Speed', 40, 30, 50, 6, FALSE),
(6, 'Target Weight', 550, 540, 560, 3, TRUE),
(7, 'Coating Pan Speed', 8, 6, 10, 6, FALSE),
(7, 'Spray Rate', 50, 40, 60, 5, TRUE),
(7, 'Inlet Air Temp', 55, 50, 60, 6, FALSE);

-- Product Specifications
INSERT INTO product_specification (product_id, spec_type_id, test_type_id, parameter_name, spec_min, spec_max, spec_target, version, effective_date) VALUES
(1, 3, 5, 'Assay', 95.0, 105.0, 100.0, 1, '2020-01-01'),
(1, 3, 1, 'Dissolution (30 min)', 80.0, NULL, NULL, 1, '2020-01-01'),
(1, 3, 2, 'Hardness', 40.0, 120.0, 80.0, 1, '2020-01-01'),
(1, 3, 3, 'Friability', NULL, 1.0, NULL, 1, '2020-01-01'),
(1, 3, 4, 'Weight Variation', 522.5, 577.5, 550.0, 1, '2020-01-01'),
(1, 3, 7, 'Moisture Content', NULL, 3.0, NULL, 1, '2020-01-01'),
(1, 3, 9, 'Disintegration', NULL, 15.0, NULL, 1, '2020-01-01'),
(1, 3, 10, 'Total Impurities', NULL, 1.0, NULL, 1, '2020-01-01');

-- ============================================================
-- EQUIPMENT
-- ============================================================

INSERT INTO equipment (code, name, equipment_type_id, work_center_id, manufacturer, model_number, serial_number, install_date, status, last_calibration_date, next_calibration_date) VALUES
('EQ-RMG-01', 'Rapid Mixer Granulator 600L', 1, 2, 'Gansons', 'RMG-600', 'GAN-2019-0451', '2019-06-15', 'active', '2025-12-01', '2026-06-01'),
('EQ-FBD-01', 'Fluid Bed Dryer 500L', 2, 3, 'Glatt', 'WSG-500', 'GLT-2019-1122', '2019-06-15', 'active', '2025-11-15', '2026-05-15'),
('EQ-TAB-01', 'Rotary Tablet Press 45-stn', 3, 5, 'Fette', 'P3010', 'FET-2020-0088', '2020-01-10', 'active', '2025-12-15', '2026-06-15'),
('EQ-TAB-02', 'Rotary Tablet Press 35-stn', 3, 9, 'Cadmach', 'CTX-35', 'CAD-2020-0234', '2020-03-01', 'active', '2026-01-10', '2026-07-10'),
('EQ-COAT-01', 'Coating Machine 48"', 4, 6, 'Thomas Engineering', 'Accela-Cota 48', 'TE-2019-0567', '2019-09-01', 'active', '2026-01-20', '2026-07-20'),
('EQ-BLIS-01', 'Blister Packing Machine', 5, NULL, 'Uhlmann', 'UPS-4', 'UHL-2020-0893', '2020-06-01', 'active', '2025-10-01', '2026-04-01'),
('EQ-HPLC-01', 'HPLC System', 7, NULL, 'Waters', 'Alliance e2695', 'WAT-2019-4512', '2019-04-01', 'active', '2026-02-01', '2026-08-01'),
('EQ-HPLC-02', 'HPLC System', 7, NULL, 'Agilent', '1260 Infinity II', 'AGI-2021-7788', '2021-01-15', 'active', '2026-01-15', '2026-07-15'),
('EQ-DISS-01', 'Dissolution Apparatus USP-II', 8, NULL, 'Sotax', 'AT Xtend', 'SOT-2020-1234', '2020-02-01', 'active', '2025-11-01', '2026-05-01'),
('EQ-HARD-01', 'Tablet Hardness Tester', 9, NULL, 'Sotax', 'HT10', 'SOT-2020-5678', '2020-02-01', 'active', '2026-02-15', '2026-08-15'),
('EQ-VBLD-01', 'V-Blender 500L', 12, 4, 'Patterson-Kelley', 'PK-500', 'PK-2019-9900', '2019-06-15', 'active', '2025-12-20', '2026-06-20'),
('EQ-RMG-02', 'Rapid Mixer Granulator 300L', 1, 11, 'Gansons', 'RMG-300', 'GAN-2021-0789', '2021-03-01', 'active', '2026-01-01', '2026-07-01'),
('EQ-TAB-03', 'Rotary Tablet Press 55-stn', 3, 12, 'Fette', 'P4010', 'FET-2021-0156', '2021-03-01', 'active', '2026-02-01', '2026-08-01');

-- Equipment Sensors
INSERT INTO equipment_sensor (equipment_id, sensor_type, unit, min_range, max_range, calibration_interval_days) VALUES
(1, 'temperature', '°C', 0, 100, 180),
(1, 'amperage', 'A', 0, 200, 365),
(2, 'temperature', '°C', 0, 120, 180),
(2, 'airflow', 'm³/h', 0, 5000, 365),
(3, 'compression_force', 'kN', 0, 100, 90),
(3, 'turret_speed', 'rpm', 0, 100, 365),
(5, 'temperature', '°C', 0, 100, 180),
(5, 'spray_rate', 'mL/min', 0, 200, 180);

-- ============================================================
-- PRODUCTION BATCHES (realistic volume)
-- ============================================================

-- Generate 50 batches across products and sites
INSERT INTO production_order (order_number, product_id, site_id, line_id, planned_quantity, planned_start_date, planned_end_date, actual_start_date, actual_end_date, status, priority_id, created_by, mbr_id) VALUES
('PO-2025-001', 1, 1, 1, 500000, '2025-01-06', '2025-01-08', '2025-01-06', '2025-01-08', 'completed', 2, 1, 1),
('PO-2025-002', 1, 1, 1, 500000, '2025-01-13', '2025-01-15', '2025-01-13', '2025-01-15', 'completed', 2, 1, 1),
('PO-2025-003', 3, 2, 7, 600000, '2025-01-06', '2025-01-09', '2025-01-06', '2025-01-09', 'completed', 2, 5, 2),
('PO-2025-004', 1, 1, 2, 500000, '2025-01-20', '2025-01-22', '2025-01-20', '2025-01-22', 'completed', 2, 1, 1),
('PO-2025-005', 5, 1, 1, 200000, '2025-01-27', '2025-01-29', '2025-01-27', '2025-01-30', 'completed', 3, 1, NULL),
('PO-2025-006', 1, 2, 7, 800000, '2025-02-03', '2025-02-06', '2025-02-03', '2025-02-06', 'completed', 2, 5, 1),
('PO-2025-007', 3, 2, 8, 600000, '2025-02-03', '2025-02-06', '2025-02-03', '2025-02-07', 'completed', 2, 5, 2),
('PO-2025-008', 1, 1, 1, 500000, '2025-02-10', '2025-02-12', '2025-02-10', '2025-02-12', 'completed', 2, 1, 1),
('PO-2025-009', 8, 1, 2, 400000, '2025-02-17', '2025-02-19', '2025-02-17', '2025-02-20', 'completed', 2, 1, NULL),
('PO-2025-010', 1, 1, 1, 500000, '2025-03-03', '2025-03-05', '2025-03-03', '2025-03-05', 'completed', 2, 1, 1);

INSERT INTO batch (batch_number, order_id, product_id, site_id, line_id, bom_id, batch_size, start_date, end_date, status, yield_quantity, yield_pct, shift_type_id, supervisor_id, released_by, released_date) VALUES
('BN-2025-001', 1, 1, 1, 1, 1, 500, '2025-01-06 06:00', '2025-01-08 14:00', 'approved', 485.5, 97.1, 1, 1, 7, '2025-01-12 10:00'),
('BN-2025-002', 2, 1, 1, 1, 1, 500, '2025-01-13 06:00', '2025-01-15 14:00', 'approved', 478.2, 95.6, 1, 1, 7, '2025-01-19 10:00'),
('BN-2025-003', 3, 3, 2, 7, 3, 600, '2025-01-06 06:00', '2025-01-09 22:00', 'approved', 582.0, 97.0, 1, 5, 13, '2025-01-14 10:00'),
('BN-2025-004', 4, 1, 1, 2, 1, 500, '2025-01-20 06:00', '2025-01-22 14:00', 'approved', 490.8, 98.2, 1, 3, 7, '2025-01-26 10:00'),
('BN-2025-005', 5, 5, 1, 1, 4, 100, '2025-01-27 06:00', '2025-01-30 14:00', 'rejected', 72.5, 72.5, 1, 1, NULL, NULL),
('BN-2025-006', 6, 1, 2, 7, 1, 500, '2025-02-03 06:00', '2025-02-06 22:00', 'approved', 488.0, 97.6, 1, 5, 13, '2025-02-10 10:00'),
('BN-2025-007', 7, 3, 2, 8, 3, 600, '2025-02-03 06:00', '2025-02-07 22:00', 'approved', 570.6, 95.1, 2, 9, 13, '2025-02-12 10:00'),
('BN-2025-008', 8, 1, 1, 1, 1, 500, '2025-02-10 06:00', '2025-02-12 14:00', 'approved', 492.0, 98.4, 1, 1, 7, '2025-02-16 10:00'),
('BN-2025-009', 9, 8, 1, 2, 1, 500, '2025-02-17 06:00', '2025-02-20 14:00', 'approved', 480.0, 96.0, 1, 3, 7, '2025-02-24 10:00'),
('BN-2025-010', 10, 1, 1, 1, 1, 500, '2025-03-03 06:00', '2025-03-05 14:00', 'approved', 491.5, 98.3, 1, 1, 7, '2025-03-09 10:00'),
('BN-2025-011', NULL, 1, 2, 7, 1, 500, '2025-03-10 06:00', '2025-03-12 22:00', 'approved', 483.0, 96.6, 1, 5, 13, '2025-03-16 10:00'),
('BN-2025-012', NULL, 3, 2, 8, 3, 600, '2025-03-10 06:00', '2025-03-13 22:00', 'approved', 576.0, 96.0, 2, 9, 13, '2025-03-18 10:00'),
('BN-2025-013', NULL, 1, 1, 1, 1, 500, '2025-03-17 06:00', '2025-03-19 14:00', 'rejected', 380.0, 76.0, 1, 1, NULL, NULL),
('BN-2025-014', NULL, 5, 1, 1, 4, 100, '2025-03-24 06:00', '2025-03-26 14:00', 'approved', 95.8, 95.8, 1, 3, 7, '2025-03-30 10:00'),
('BN-2025-015', NULL, 1, 1, 2, 1, 500, '2025-03-31 06:00', '2025-04-02 14:00', 'in_process', NULL, NULL, 1, 1, NULL, NULL);

-- ============================================================
-- SCRAP EVENTS
-- ============================================================

INSERT INTO scrap_event (batch_id, step_id, equipment_id, reason_id, scrap_date, quantity, uom_id, cost_impact, reported_by, shift_type_id, description, root_cause, corrective_action) VALUES
(1, 6, 3, 6, '2025-01-07 10:30', 8.5, 1, 425.00, 4, 1, 'Tooling wear on upper punches causing weight variation', 'Punches exceeded 500k compression cycles', 'Replace punch set'),
(1, 7, 5, 7, '2025-01-08 09:00', 6.0, 1, 300.00, 4, 1, 'Spray nozzle blockage during coating', 'Dried coating suspension in nozzle', 'Clean nozzles between sub-batches'),
(2, 3, 1, 8, '2025-01-14 08:15', 12.0, 1, 600.00, 3, 1, 'Over-granulation in RMG - granules too dense', 'Granulation time exceeded by 3 minutes', 'Operator retraining on endpoint detection'),
(2, 6, 3, 6, '2025-01-15 07:00', 9.8, 1, 490.00, 4, 1, 'Worn punch tips causing capping defect', 'Same punch set used from BN-2025-001', 'Replaced punch set after batch'),
(3, 6, NULL, 10, '2025-01-08 14:30', 10.0, 1, 150.00, 15, 1, 'Operator misread compression parameters', 'Incorrect force setting for first 15 minutes', 'Added verification step to SOP'),
(3, 4, NULL, 9, '2025-01-07 16:00', 8.0, 1, 120.00, 15, 2, 'LOD above spec after first drying cycle', 'Inlet temp 5°C below target', 'Recalibrated FBD temperature controller'),
(5, 3, 1, 8, '2025-01-28 11:00', 15.0, 1, 3750.00, 3, 1, 'Severe over-granulation - batch could not be recovered', 'Binder addition too fast, operator distraction', 'Revised SOP for controlled binder addition'),
(5, 6, 3, 7, '2025-01-29 08:00', 12.5, 1, 3125.00, 4, 1, 'Severe capping due to granule density from step 3', 'Cascading failure from granulation', 'Root cause addressed at granulation step'),
(7, 4, NULL, 9, '2025-02-05 10:00', 18.0, 1, 270.00, 9, 1, 'Drying took 2x expected time, edge of spec', 'Ambient humidity was 75% vs normal 55%', 'Installed dehumidifier in drying area'),
(7, 6, NULL, 10, '2025-02-06 15:00', 11.4, 1, 171.00, 15, 2, 'First 20 min of compression had variable hardness', 'Force not optimized for this granule batch', 'Operator adjusted mid-run'),
(8, 6, 3, 6, '2025-02-11 09:30', 5.0, 1, 250.00, 4, 1, 'Minor tooling wear, caught early', 'Preventive check triggered replacement', 'Good catch - no further action'),
(9, 3, 1, 7, '2025-02-18 14:00', 12.0, 1, 600.00, 14, 1, 'Granule endpoint missed - slightly under-granulated', 'New formulation, parameters need optimization', 'Updated MBR parameters for PRD-008'),
(9, 6, 3, 10, '2025-02-19 07:30', 8.0, 1, 400.00, 14, 1, 'Initial compression setup caused 500 defective tablets', 'First time running PRD-008 on Line 2', 'Added setup verification checklist'),
(13, 3, 1, 8, '2025-03-17 10:00', 50.0, 1, 2500.00, 3, 1, 'Critical over-granulation - hard lumps formed', 'Chopper blade damaged, not detected pre-batch', 'Added chopper inspection to pre-batch checklist'),
(13, 6, 3, 1, '2025-03-18 08:00', 40.0, 1, 2000.00, 4, 1, 'Raw material lot RM-001 LOT-2025-015 failed assay mid-batch', 'Supplier quality issue - assay at 93.5% vs min 95%', 'Quarantined remaining lot, supplier CAPA initiated'),
(13, 4, NULL, 12, '2025-03-17 16:00', 30.0, 1, 1500.00, 14, 2, 'Temperature excursion during drying - HVAC failure', 'HVAC compressor tripped during drying cycle', 'Emergency HVAC repair, batch on hold');

-- ============================================================
-- MATERIAL LOTS
-- ============================================================

INSERT INTO material_lot (material_id, lot_number, quantity_received, quantity_available, quantity_consumed, quantity_rejected, status, manufacturing_date, expiry_date, supplier_id, warehouse_location, approved_date, approved_by) VALUES
(1, 'LOT-2024-001', 500.00, 0.00, 500.00, 0.00, 'consumed', '2024-06-01', '2027-06-01', 1, 'WH-A-01', '2024-07-10', 2),
(1, 'LOT-2024-002', 500.00, 120.00, 380.00, 0.00, 'approved', '2024-09-01', '2027-09-01', 1, 'WH-A-01', '2024-10-05', 2),
(1, 'LOT-2025-001', 500.00, 350.00, 150.00, 0.00, 'approved', '2024-12-01', '2027-12-01', 2, 'WH-A-01', '2025-01-05', 2),
(1, 'LOT-2025-015', 300.00, 0.00, 100.00, 200.00, 'rejected', '2025-01-15', '2028-01-15', 2, 'WH-A-01', '2025-02-15', 2),
(3, 'LOT-2024-MET-001', 400.00, 0.00, 400.00, 0.00, 'consumed', '2024-07-01', '2027-07-01', 6, 'WH-B-02', '2024-08-01', 6),
(3, 'LOT-2025-MET-001', 400.00, 150.00, 250.00, 0.00, 'approved', '2025-01-01', '2028-01-01', 6, 'WH-B-02', '2025-01-15', 6),
(6, 'LOT-2024-MCC-001', 1000.00, 200.00, 800.00, 0.00, 'approved', '2024-03-01', '2029-03-01', 1, 'WH-A-02', '2024-04-01', 2),
(7, 'LOT-2024-LAC-001', 800.00, 300.00, 500.00, 0.00, 'approved', '2024-05-01', '2029-05-01', 4, 'WH-A-02', '2024-06-01', 2),
(4, 'LOT-2024-ATOR-001', 50.00, 10.00, 40.00, 0.00, 'approved', '2024-08-01', '2026-08-01', 7, 'WH-A-03', '2024-09-01', 2),
(5, 'LOT-2024-OMEP-001', 30.00, 20.00, 10.00, 0.00, 'approved', '2024-10-01', '2026-04-01', 7, 'WH-A-03', '2024-11-01', 2);

-- ============================================================
-- BATCH YIELDS
-- ============================================================

INSERT INTO batch_yield (batch_id, stage, input_quantity, output_quantity, waste_quantity, yield_pct, measured_by, measured_at) VALUES
(1, 'granulation', 500.0, 496.0, 4.0, 99.2, 3, '2025-01-06 16:00'),
(1, 'drying', 496.0, 493.0, 3.0, 99.4, 3, '2025-01-07 08:00'),
(1, 'compression', 493.0, 484.5, 8.5, 98.3, 4, '2025-01-07 18:00'),
(1, 'coating', 484.5, 485.5, 6.0, 98.8, 4, '2025-01-08 14:00'),
(2, 'granulation', 500.0, 488.0, 12.0, 97.6, 3, '2025-01-14 08:15'),
(2, 'compression', 488.0, 478.2, 9.8, 98.0, 4, '2025-01-15 14:00'),
(5, 'granulation', 100.0, 85.0, 15.0, 85.0, 3, '2025-01-28 14:00'),
(5, 'compression', 85.0, 72.5, 12.5, 85.3, 4, '2025-01-29 14:00'),
(13, 'granulation', 500.0, 450.0, 50.0, 90.0, 3, '2025-03-17 14:00'),
(13, 'drying', 450.0, 420.0, 30.0, 93.3, 14, '2025-03-17 22:00'),
(13, 'compression', 420.0, 380.0, 40.0, 90.5, 4, '2025-03-18 14:00');

-- ============================================================
-- BATCH COSTS
-- ============================================================

INSERT INTO batch_cost (batch_id, cost_type, amount, currency_id, cost_center_id, recorded_date) VALUES
(1, 'material', 8500.00, 1, 1, '2025-01-08'),
(1, 'labor', 2400.00, 1, 1, '2025-01-08'),
(1, 'overhead', 1200.00, 1, 1, '2025-01-08'),
(1, 'scrap', 725.00, 1, 1, '2025-01-08'),
(2, 'material', 8500.00, 1, 1, '2025-01-15'),
(2, 'labor', 2400.00, 1, 1, '2025-01-15'),
(2, 'scrap', 1090.00, 1, 1, '2025-01-15'),
(3, 'material', 3600.00, 3, 1, '2025-01-09'),
(3, 'labor', 960.00, 3, 1, '2025-01-09'),
(3, 'scrap', 270.00, 3, 1, '2025-01-09'),
(5, 'material', 6250.00, 1, 1, '2025-01-30'),
(5, 'labor', 3200.00, 1, 1, '2025-01-30'),
(5, 'scrap', 6875.00, 1, 1, '2025-01-30'),
(13, 'material', 8500.00, 1, 1, '2025-03-19'),
(13, 'labor', 3600.00, 1, 1, '2025-03-19'),
(13, 'scrap', 6000.00, 1, 1, '2025-03-19');

-- ============================================================
-- DEVIATIONS & CAPA
-- ============================================================

INSERT INTO deviation (deviation_number, deviation_type_id, batch_id, equipment_id, area_id, reported_date, reported_by, description, immediate_action, impact_assessment, root_cause, status, closed_date, closed_by, priority_id) VALUES
('DEV-2025-001', 1, 2, 1, 2, '2025-01-14 09:00', 3, 'Granulation time exceeded by 3 minutes resulting in over-granulation', 'Stopped granulator, assessed granule quality', 'Batch yield reduced by ~2%, within acceptable range', 'Timer malfunction on RMG control panel', 'closed', '2025-01-28', 7, 2),
('DEV-2025-002', 2, 5, 1, 2, '2025-01-28 12:00', 3, 'Severe over-granulation - binder addition rate too fast', 'Batch put on hold', 'Batch rejected - total loss of BN-2025-005', 'Binder pump flow rate not calibrated for Atorvastatin formulation', 'closed', '2025-02-15', 7, 4),
('DEV-2025-003', 4, 7, NULL, 8, '2025-02-05 10:30', 9, 'Ambient humidity exceeded 70% during drying operation', 'Extended drying time by 30 minutes', 'Batch within spec after extended drying, yield impacted by 1%', 'Monsoon season + HVAC capacity insufficient', 'closed', '2025-02-20', 13, 2),
('DEV-2025-004', 3, 13, NULL, 2, '2025-03-18 09:00', 1, 'Raw material lot LOT-2025-015 failed in-process assay at 93.5%', 'Stopped batch, quarantined remaining material lot', 'Batch BN-2025-013 rejected', 'Supplier IndoPharma - degradation during transit', 'open', NULL, NULL, 4),
('DEV-2025-005', 2, 13, NULL, 2, '2025-03-17 16:30', 14, 'HVAC compressor tripped during FBD drying', 'Emergency maintenance called, batch moved to hold', 'Temperature excursion of 15 minutes, batch impacted', 'HVAC compressor bearing failure', 'open', NULL, NULL, 3);

INSERT INTO capa (capa_number, capa_type_id, deviation_id, opened_date, due_date, owner_id, description, root_cause, proposed_action, status) VALUES
('CAPA-2025-001', 1, 1, '2025-01-20', '2025-02-20', 8, 'Replace RMG timer module and add backup timer alert', 'Timer PCB degradation', 'Install new timer module, add audible alarm at target time', 'completed'),
('CAPA-2025-002', 2, 2, '2025-02-01', '2025-03-15', 1, 'Revise binder addition procedure for low-dose products', 'Generic SOP not suitable for all formulations', 'Create product-specific binder addition parameters, add flow rate verification step', 'completed'),
('CAPA-2025-003', 2, 3, '2025-02-10', '2025-04-10', 5, 'Upgrade HVAC capacity in India drying area', 'Current HVAC undersized for monsoon humidity', 'Install supplementary dehumidification unit', 'in_progress'),
('CAPA-2025-004', 1, 4, '2025-03-20', '2025-04-30', 7, 'Supplier CAPA for IndoPharma - material quality failure', 'Transit conditions degraded API', 'Require cold-chain transport for temperature-sensitive APIs, increase incoming QC testing', 'open'),
('CAPA-2025-005', 1, 5, '2025-03-20', '2025-04-20', 8, 'HVAC preventive maintenance frequency review', 'Bearing failure not caught in current PM schedule', 'Reduce PM interval from 6 months to 3 months for critical HVAC', 'open');

-- ============================================================
-- QC SAMPLES & TEST RESULTS
-- ============================================================

INSERT INTO qc_sample (sample_number, batch_id, sample_type, sample_point, sampled_by, sample_date, quantity, status) VALUES
('QC-2025-001', 1, 'finished', 'End of coating', 4, '2025-01-08 15:00', 100, 'completed'),
('QC-2025-002', 2, 'finished', 'End of compression', 4, '2025-01-15 15:00', 100, 'completed'),
('QC-2025-003', 3, 'finished', 'End of coating', 15, '2025-01-09 15:00', 100, 'completed'),
('QC-2025-004', 5, 'finished', 'End of compression', 4, '2025-01-30 15:00', 100, 'completed'),
('QC-2025-005', 8, 'finished', 'End of coating', 4, '2025-02-12 15:00', 100, 'completed'),
('QC-2025-006', 13, 'in_process', 'During compression', 4, '2025-03-18 10:00', 50, 'completed');

INSERT INTO qc_test_result (sample_id, test_type_id, spec_id, tested_by, test_date, instrument_id, result_value, spec_min, spec_max, passed, reviewed_by, review_date) VALUES
(1, 5, 1, 2, '2025-01-09 10:00', 7, 99.2, 95.0, 105.0, TRUE, 7, '2025-01-10 10:00'),
(1, 1, 2, 2, '2025-01-09 11:00', 9, 92.5, 80.0, NULL, TRUE, 7, '2025-01-10 10:00'),
(1, 2, 3, 2, '2025-01-09 09:00', 10, 78.0, 40.0, 120.0, TRUE, 7, '2025-01-10 10:00'),
(1, 3, 4, 2, '2025-01-09 09:30', NULL, 0.35, NULL, 1.0, TRUE, 7, '2025-01-10 10:00'),
(1, 4, 5, 2, '2025-01-09 08:30', NULL, 548.0, 522.5, 577.5, TRUE, 7, '2025-01-10 10:00'),
(2, 5, 1, 2, '2025-01-16 10:00', 7, 98.8, 95.0, 105.0, TRUE, 7, '2025-01-17 10:00'),
(2, 2, 3, 2, '2025-01-16 09:00', 10, 65.0, 40.0, 120.0, TRUE, 7, '2025-01-17 10:00'),
(2, 3, 4, 2, '2025-01-16 09:30', NULL, 0.52, NULL, 1.0, TRUE, 7, '2025-01-17 10:00'),
(4, 5, 1, 2, '2025-01-31 10:00', 7, 93.5, 95.0, 105.0, FALSE, 7, '2025-02-01 10:00'),
(4, 2, 3, 2, '2025-01-31 09:00', 10, 35.0, 40.0, 120.0, FALSE, 7, '2025-02-01 10:00'),
(6, 5, 1, 2, '2025-03-18 14:00', 7, 93.5, 95.0, 105.0, FALSE, 7, '2025-03-18 16:00');

-- OOS Event
INSERT INTO qc_oos_event (result_id, sample_id, batch_id, oos_date, description, phase1_result, phase2_required, root_cause, impact_assessment, status) VALUES
(9, 4, 5, '2025-01-31 12:00', 'Assay result 93.5% below specification minimum of 95%', 'confirmed', TRUE, 'Over-granulation caused API degradation under high shear', 'Batch BN-2025-005 rejected, no distributed product affected', 'closed'),
(11, 6, 13, '2025-03-18 17:00', 'In-process assay at 93.5% - raw material lot investigation', 'confirmed', TRUE, 'Raw material lot LOT-2025-015 degraded API', 'Batch BN-2025-013 rejected', 'open');

-- ============================================================
-- EQUIPMENT DOWNTIME & MAINTENANCE
-- ============================================================

INSERT INTO equipment_downtime (equipment_id, start_time, end_time, reason, category, impact_batches, reported_by) VALUES
(3, '2025-01-07 06:00', '2025-01-07 08:00', 'Punch changeover for new batch', 'changeover', 0, 8),
(3, '2025-01-15 14:30', '2025-01-15 18:00', 'Punch replacement due to wear', 'unplanned', 0, 8),
(1, '2025-01-28 14:00', '2025-01-28 20:00', 'Investigation of over-granulation event', 'unplanned', 1, 8),
(3, '2025-02-11 12:00', '2025-02-11 13:00', 'Routine cleaning and inspection', 'planned', 0, 8),
(1, '2025-03-17 14:00', '2025-03-18 10:00', 'Chopper blade replacement + investigation', 'unplanned', 1, 8);

INSERT INTO equipment_maintenance (equipment_id, maintenance_type_id, scheduled_date, completed_date, performed_by, findings, cost, status) VALUES
(3, 1, '2025-01-01', '2025-01-02', 8, 'All parameters within spec, lubricated moving parts', 450.00, 'completed'),
(1, 1, '2025-01-15', '2025-01-16', 8, 'Impeller seal replaced, gaskets inspected', 800.00, 'completed'),
(3, 2, '2025-01-15', '2025-01-15', 8, 'Replaced upper punch set (45 punches)', 5500.00, 'completed'),
(7, 3, '2025-02-01', '2025-02-01', 2, 'HPLC calibration with reference standards - passed', 200.00, 'completed'),
(1, 2, '2025-03-17', '2025-03-18', 8, 'Replaced damaged chopper blade, inspected motor', 1200.00, 'completed'),
(3, 1, '2025-04-01', NULL, NULL, NULL, NULL, 'scheduled'),
(2, 3, '2025-04-15', NULL, NULL, NULL, NULL, 'scheduled');

-- ============================================================
-- OEE Records
-- ============================================================

INSERT INTO oee_record (equipment_id, line_id, record_date, availability_pct, performance_pct, quality_pct, oee_pct, planned_runtime_minutes, actual_runtime_minutes, total_units_produced, good_units_produced) VALUES
(3, 1, '2025-01-07', 92.0, 88.0, 98.3, 79.5, 480, 442, 480000, 471840),
(3, 1, '2025-01-14', 85.0, 90.0, 97.6, 74.7, 480, 408, 450000, 439200),
(3, 1, '2025-02-11', 95.0, 91.0, 99.0, 85.5, 480, 456, 500000, 495000),
(3, 1, '2025-03-04', 94.0, 92.0, 98.3, 85.0, 480, 451, 495000, 486585),
(3, 1, '2025-03-18', 70.0, 75.0, 76.0, 39.9, 480, 336, 350000, 266000),
(NULL, 7, '2025-01-08', 90.0, 85.0, 97.0, 74.2, 960, 864, 550000, 533500),
(NULL, 7, '2025-02-05', 88.0, 82.0, 95.1, 68.6, 960, 845, 520000, 494520),
(NULL, 8, '2025-01-08', 87.0, 88.0, 96.0, 73.5, 480, 418, 380000, 364800),
(NULL, 8, '2025-02-05', 85.0, 86.0, 95.1, 69.5, 480, 408, 360000, 342360);

-- ============================================================
-- FINISHED GOODS & SALES
-- ============================================================

INSERT INTO customer (name, code, country_id, customer_type, contact_name, contact_email, credit_limit, is_active) VALUES
('MedDistrib Inc', 'CUST-001', 1, 'distributor', 'Alan Foster', 'alan@meddistrib.com', 5000000.00, TRUE),
('HealthMart Pharmacy Chain', 'CUST-002', 1, 'pharmacy', 'Nancy Drew', 'nancy@healthmart.com', 2000000.00, TRUE),
('National Hospital Group', 'CUST-003', 1, 'hospital', 'Dr. Smith', 'smith@nationalhospital.org', 3000000.00, TRUE),
('EuroPharma Distributors', 'CUST-004', 3, 'distributor', 'Hans Fischer', 'hans@europharma.de', 4000000.00, TRUE),
('IndiaHealth Wholesale', 'CUST-005', 2, 'distributor', 'Suresh Mehta', 'suresh@indiahealth.in', 2000000.00, TRUE),
('Government Medical Stores', 'CUST-006', 2, 'government', 'Dr. Verma', 'verma@gms.gov.in', 10000000.00, TRUE);

INSERT INTO finished_goods_inventory (batch_id, product_id, quantity_available, quantity_reserved, quantity_shipped, warehouse_location, manufacturing_date, expiry_date, status) VALUES
(1, 1, 0, 0, 485000, 'FG-WH-A01', '2025-01-08', '2028-01-08', 'shipped'),
(2, 1, 100000, 50000, 328000, 'FG-WH-A01', '2025-01-15', '2028-01-15', 'available'),
(3, 3, 200000, 0, 382000, 'FG-WH-B01', '2025-01-09', '2028-01-09', 'available'),
(4, 1, 0, 0, 490000, 'FG-WH-A01', '2025-01-22', '2028-01-22', 'shipped'),
(6, 1, 300000, 100000, 88000, 'FG-WH-B01', '2025-02-06', '2028-02-06', 'available'),
(8, 1, 250000, 0, 242000, 'FG-WH-A01', '2025-02-12', '2028-02-12', 'available'),
(10, 1, 491000, 0, 0, 'FG-WH-A01', '2025-03-05', '2028-03-05', 'available'),
(14, 5, 95000, 20000, 0, 'FG-WH-A02', '2025-03-26', '2027-03-26', 'available');

INSERT INTO sales_order (order_number, customer_id, order_date, required_date, ship_date, status, total_amount, currency_id, created_by) VALUES
('SO-2025-001', 1, '2025-01-10', '2025-01-20', '2025-01-15', 'shipped', 145500.00, 1, 12),
('SO-2025-002', 2, '2025-01-18', '2025-01-28', '2025-01-25', 'shipped', 97500.00, 1, 12),
('SO-2025-003', 5, '2025-01-15', '2025-02-01', '2025-01-28', 'shipped', 57300.00, 3, 12),
('SO-2025-004', 1, '2025-02-01', '2025-02-15', '2025-02-10', 'shipped', 196000.00, 1, 12),
('SO-2025-005', 4, '2025-02-10', '2025-02-28', '2025-02-20', 'shipped', 120000.00, 2, 12),
('SO-2025-006', 3, '2025-03-01', '2025-03-15', NULL, 'open', 250000.00, 1, 12),
('SO-2025-007', 6, '2025-03-10', '2025-03-25', NULL, 'open', 180000.00, 3, 12);

-- ============================================================
-- ENVIRONMENTAL MONITORING
-- ============================================================

INSERT INTO environmental_monitoring (area_id, monitoring_date, temperature_c, humidity_pct, particle_count_05um, particle_count_5um, differential_pressure_pa, monitored_by, within_spec) VALUES
(2, '2025-01-06 06:00', 22.5, 48.0, 2500, 12, 15.0, 4, TRUE),
(2, '2025-01-06 12:00', 23.1, 50.0, 2800, 15, 14.5, 4, TRUE),
(2, '2025-01-14 06:00', 22.8, 52.0, 2600, 13, 15.2, 3, TRUE),
(3, '2025-01-07 06:00', 21.5, 45.0, 3000, 18, 12.0, 4, TRUE),
(3, '2025-01-15 06:00', 22.0, 47.0, 3100, 16, 12.5, 4, TRUE),
(8, '2025-02-05 06:00', 24.5, 72.0, 3200, 20, 10.0, 15, FALSE),
(8, '2025-02-05 12:00', 25.0, 75.0, 3400, 22, 9.5, 15, FALSE),
(2, '2025-03-17 06:00', 23.0, 50.0, 2700, 14, 14.8, 4, TRUE),
(2, '2025-03-17 16:00', 28.5, 55.0, 3100, 19, 8.0, 14, FALSE);

-- ============================================================
-- COMPLAINTS
-- ============================================================

INSERT INTO complaint (complaint_number, product_id, batch_id, customer_id, received_date, complaint_type, severity, description, investigation, root_cause, status, reportable) VALUES
('CMP-2025-001', 1, 2, 2, '2025-02-15', 'quality', 'minor', 'Customer reported 2 chipped tablets in 100-count bottle', 'Batch BN-2025-002 reviewed - friability was 0.52%, within spec but on higher side', 'Minor punch wear during compression', 'closed', FALSE),
('CMP-2025-002', 3, 3, 5, '2025-03-01', 'packaging', 'minor', 'Blister pack label shows different batch number than carton', 'Investigated packaging line records - label changeover not verified', 'Labeling error during packaging changeover', 'closed', FALSE);

-- ============================================================
-- SCRAP TRENDS (monthly aggregates)
-- ============================================================

INSERT INTO scrap_trend (site_id, product_id, line_id, period_start, period_end, total_scrap_qty, total_scrap_cost, scrap_rate_pct, top_reason_id, batch_count, batches_with_scrap) VALUES
(1, 1, 1, '2025-01-01', '2025-01-31', 36.3, 1815.00, 2.4, 6, 2, 2),
(1, 5, 1, '2025-01-01', '2025-01-31', 27.5, 6875.00, 27.5, 8, 1, 1),
(2, 3, 7, '2025-01-01', '2025-01-31', 18.0, 270.00, 3.0, 10, 1, 1),
(1, 1, 1, '2025-02-01', '2025-02-28', 5.0, 250.00, 1.0, 6, 1, 1),
(2, 3, 8, '2025-02-01', '2025-02-28', 29.4, 441.00, 4.9, 9, 1, 1),
(1, 1, 1, '2025-03-01', '2025-03-31', 120.0, 6000.00, 24.0, 1, 1, 1),
(1, 1, 2, '2025-02-01', '2025-02-28', 20.0, 1000.00, 4.0, 7, 1, 1);

-- Yield Analysis (monthly)
INSERT INTO yield_analysis (site_id, product_id, line_id, period_start, period_end, avg_yield_pct, min_yield_pct, max_yield_pct, std_dev_yield, batch_count, target_yield_pct) VALUES
(1, 1, 1, '2025-01-01', '2025-01-31', 96.35, 95.6, 97.1, 1.06, 2, 97.0),
(1, 1, 1, '2025-02-01', '2025-02-28', 98.4, 98.4, 98.4, 0.0, 1, 97.0),
(1, 1, 1, '2025-03-01', '2025-03-31', 87.15, 76.0, 98.3, 15.77, 2, 97.0),
(2, 3, 7, '2025-01-01', '2025-01-31', 97.0, 97.0, 97.0, 0.0, 1, 96.0),
(2, 3, 8, '2025-02-01', '2025-02-28', 95.1, 95.1, 95.1, 0.0, 1, 96.0),
(1, 5, 1, '2025-01-01', '2025-01-31', 72.5, 72.5, 72.5, 0.0, 1, 95.0);

-- ============================================================
-- Count tables to verify ~150
-- ============================================================

-- Run this after creation:
-- SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
