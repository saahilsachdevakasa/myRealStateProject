#!/usr/bin/env python3
"""
Export RE_CRM_Demo_Inventory_Master.xlsx sheets to loader-ready CSVs.

Headers are aligned with Salesforce API field names per the Phase 1 data model.
Roll-up and formula fields are stripped (they compute server-side).
Lookup fields use the parent's external-ID value (loader uses `:extIdField` convention).
"""
import pandas as pd
from pathlib import Path

SRC = Path("data/_inventory-master.xlsx")
OUT = Path("data")

def save(df: pd.DataFrame, name: str) -> None:
    path = OUT / name
    df.to_csv(path, index=False, encoding="utf-8")
    print(f"  {name}: {len(df)} rows")

xls = pd.ExcelFile(SRC)
print(f"Reading {SRC} — {len(xls.sheet_names)} sheets")

# ---------- Projects ----------
# Source headers: Project_Code__c | Name | Project_Type__c | Location | Launch_Status__c
#                | RERA_Number__c | RERA_State__c | Delivery_Date__c | Towers | Total_Units | Positioning
# Drop: Towers, Total_Units (roll-ups, computed server-side)
projects = pd.read_excel(SRC, sheet_name="Projects")
projects = projects[[
    "Project_Code__c", "Name", "Project_Type__c",
    "Location", "Launch_Status__c",
    "RERA_Number__c", "RERA_State__c", "Delivery_Date__c",
    "Positioning"
]].rename(columns={"Positioning": "Positioning__c", "Location": "Location__c"})
save(projects, "projects.csv")

# ---------- Towers ----------
# Source: Tower_Code__c | Project_Code__c | Name | Type | Floors | Units_Per_Floor
#         | Construction_Status__c | Configuration_Mix
# Salesforce target fields: Name, Tower_Code__c, Project__r.Project_Code__c (external ID lookup),
#   Tower_Type__c, Total_Floors__c, Units_Per_Floor__c, Construction_Status__c, Configuration_Mix__c
# We'll write a "Tower_Number__c" column derived from Tower_Code (the '01' part)
towers = pd.read_excel(SRC, sheet_name="Towers_Blocks")
towers["Tower_Number__c"] = towers["Tower_Code__c"].str[-2:].astype(int)
towers["Tower_Type__c"] = towers["Type"].map({
    "Residential Tower": "Residential_Tower",
    "Commercial Block": "Commercial_Block",
})
towers_out = pd.DataFrame({
    "Name": towers["Tower_Code__c"],
    "Tower_Code__c": towers["Tower_Code__c"],
    "Project__r:Project_Code__c": towers["Project_Code__c"],   # external ID lookup hint
    "Tower_Number__c": towers["Tower_Number__c"],
    "Tower_Type__c": towers["Tower_Type__c"],
    "Total_Floors__c": towers["Floors"],
    "Units_Per_Floor__c": towers["Units_Per_Floor"],
    "Construction_Status__c": towers["Construction_Status__c"],
    "Configuration_Mix__c": towers["Configuration_Mix"],
})
save(towers_out, "towers.csv")

# ---------- Residential Units ----------
# Source: Unit_Code__c | Tower_Code__c | Project_Code__c | Floor | Unit_Number | Configuration
#         | Carpet_Area_sqft | Super_BuiltUp_Area_sqft | Facing | Corner_Unit | Park_Facing
#         | Base_Price_INR | Unit_Status__c
# Target: Name (formula server-side, omit), Unit_Code__c (formula, omit),
#   Tower__r:Tower_Code__c, Floor__c, Unit_Number__c, Unit_Type_Class__c, Configuration__c,
#   Carpet_Area_sqft__c, Super_BuiltUp_Area_sqft__c, Facing__c, Corner_Unit__c, Park_Facing__c,
#   BSP_Per_Sqft__c (we seed directly — Base_Price__c is the formula),
#   Unit_Status__c, BuiltUp_Area_sqft__c (derived ~ 0.85x SBA)
units_r = pd.read_excel(SRC, sheet_name="Units_Residential")
units_r_out = pd.DataFrame({
    "Tower__r:Tower_Code__c": units_r["Tower_Code__c"],
    "Floor__c": units_r["Floor"],
    "Unit_Number__c": units_r["Unit_Number"],
    "Unit_Type_Class__c": "Residential",
    "Configuration__c": units_r["Configuration"],
    "Carpet_Area_sqft__c": units_r["Carpet_Area_sqft"],
    "BuiltUp_Area_sqft__c": (units_r["Carpet_Area_sqft"] * 1.2).astype(int),  # typical multiplier
    "Super_BuiltUp_Area_sqft__c": units_r["Super_BuiltUp_Area_sqft"],
    "Facing__c": units_r["Facing"],
    "Corner_Unit__c": units_r["Corner_Unit"].map({"Yes": "true", "No": "false"}),
    "Park_Facing__c": units_r["Park_Facing"].map({"Yes": "true", "No": "false"}),
    # BSP_Per_Sqft is Base_Price / SBA / (1 + premiums). Simplified for seed: back-compute from Base/SBA.
    "BSP_Per_Sqft__c": (units_r["Base_Price_INR"] / units_r["Super_BuiltUp_Area_sqft"]).round(0).astype(int),
    "Unit_Status__c": units_r["Unit_Status__c"],
})
save(units_r_out, "units-residential.csv")

# ---------- Commercial Units ----------
units_c = pd.read_excel(SRC, sheet_name="Units_Commercial")
units_c_out = pd.DataFrame({
    "Tower__r:Tower_Code__c": units_c["Block_Code__c"],
    "Floor__c": units_c["Floor"],
    "Unit_Number__c": units_c["Shop_Number"],
    "Unit_Type_Class__c": "Shop",
    "Configuration__c": units_c["Shop_Type"],
    "Shop_Type__c": units_c["Shop_Type"],
    "Carpet_Area_sqft__c": units_c["Carpet_Area_sqft"],
    "Super_BuiltUp_Area_sqft__c": (units_c["Carpet_Area_sqft"] * 1.3).astype(int),  # commercial loading
    "Frontage_ft__c": units_c["Frontage_ft"],
    "BSP_Per_Sqft__c": (units_c["Base_Price_INR"] / units_c["Carpet_Area_sqft"]).round(0).astype(int),
    "Unit_Status__c": units_c["Unit_Status__c"],
})
save(units_c_out, "units-commercial.csv")

# ---------- Channel Partners (Accounts) ----------
cps = pd.read_excel(SRC, sheet_name="CP_Master")
# Target fields on Account (RT = Channel_Partner):
#   Name, RecordTypeId (resolved by dev name via :DeveloperName convention), PAN__c, GSTIN__c,
#   RERA_Number__c, RERA_State__c, CP_Tier__c, Empanelment_Date__c, CP_Status__c,
#   Phone, primary Contact handled separately (Contact child records)
cps_out = pd.DataFrame({
    "Name": cps["CP_Name"],
    "RecordType:DeveloperName": "Channel_Partner",  # loader resolves RT by developer name
    "PAN__c": cps["PAN"],
    "GSTIN__c": cps["GSTIN"],
    "RERA_Number__c": cps["RERA_Number"],
    "RERA_State__c": cps["RERA_State"],
    "CP_Tier__c": cps["Tier"],
    "Empanelment_Date__c": cps["Empanelment_Date"],
    "CP_Status__c": cps["Status"].map({"Active": "Active"}).fillna("Active"),
    "Phone": cps["Phone"],
    # Note: primary contact (name, email) and CP code (CP-26-XXXX) must be created separately
    "External_CP_Code__c": cps["CP_Code"],  # for downstream lookup by rate cards
})
save(cps_out, "cps.csv")

# ---------- Payment Plans (two files: plans + milestones) ----------
pp = pd.read_excel(SRC, sheet_name="Payment_Plans")
# Filter out trailing validation rows that aren't plan data
pp = pp[pp["Plan_Code"].isin(["CLP", "DLP", "PLP"])].reset_index(drop=True)
# Unique plans from Plan_Code
plans_unique = pp[["Plan_Code", "Plan_Name"]].drop_duplicates().reset_index(drop=True)
plans_out = pd.DataFrame({
    "Name": plans_unique["Plan_Name"],
    "Plan_Code__c": plans_unique["Plan_Code"],
    "Active__c": "true",
    "Applicable_Project_Types__c": "Residential;Commercial",
})
save(plans_out, "payment-plans.csv")

milestones_out = pd.DataFrame({
    "Payment_Plan__r:Plan_Code__c": pp["Plan_Code"],
    "Sequence__c": pp["Milestone_Seq"],
    "Trigger__c": pp["Milestone_Trigger"],
    "Trigger_Type__c": pp["Plan_Code"].map({
        "CLP": "Construction", "DLP": "Time-Based", "PLP": "Possession"
    }),
    "Percentage__c": pp["Percentage_Of_Total"],
    "Description__c": pp["Description"].fillna(""),
    "Active__c": "true",
})
save(milestones_out, "payment-plan-milestones.csv")

# ---------- Commission Rate Cards ----------
rc = pd.read_excel(SRC, sheet_name="Commission_RateCard")
# Percent values come in as decimals like 0.5 (=0.50%). Match SF percent-field semantics.
rc_out = pd.DataFrame({
    "Project__r:Project_Code__c": rc["Project_Code__c"],
    "CP_Tier__c": rc["CP_Tier"],
    "Booking_Pct__c": rc["Milestone_Booking_Pct"],
    "Agreement_Pct__c": rc["Milestone_Agreement_Pct"],
    "Registration_Pct__c": rc["Milestone_Registration_Pct"],
    "Effective_From__c": rc["Effective_From"],
    "Notes__c": rc["Notes"],
})
save(rc_out, "rate-cards.csv")

print("\nDone. All CSVs in data/")
