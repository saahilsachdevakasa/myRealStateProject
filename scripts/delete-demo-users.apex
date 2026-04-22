// =============================================================================
// delete-demo-users.apex
//
// Deactivates all demo users seeded by scripts/seed-demo-users.apex.
//
// Salesforce does not allow hard-deleting User records, so this script:
//   1. Revokes PermissionSetAssignments referencing RECRM_* permission sets.
//   2. Sets IsActive=false.
//   3. Renames Username to 'archived_<timestamp>_<original>' so the canonical
//      demo usernames are freed for a subsequent re-seed.
//
// Idempotency:
//   Users already renamed to 'archived_*' are excluded by the WHERE clause,
//   so re-running is a no-op.
//
// Run with:
//   sf apex run --file scripts/delete-demo-users.apex --target-org re-crm-sdo
// =============================================================================

List<User> toDeactivate = [
    SELECT Id, Username, IsActive
    FROM User
    WHERE Username LIKE '%@recrm-demo.invalid'
      AND (NOT Username LIKE 'archived_%')
];

if (toDeactivate.isEmpty()) {
    System.debug(LoggingLevel.INFO, 'No active RECRM demo users to deactivate.');
    return;
}

Set<Id> userIds = new Set<Id>();
for (User u : toDeactivate) { userIds.add(u.Id); }

// Revoke RECRM permission-set assignments first
List<PermissionSetAssignment> psas = [
    SELECT Id FROM PermissionSetAssignment
    WHERE AssigneeId IN :userIds
      AND PermissionSet.Name LIKE 'RECRM_%'
];
if (!psas.isEmpty()) {
    delete psas;
}

// Deactivate + rename
String ts = String.valueOf(System.now().getTime());
List<User> toUpdate = new List<User>();
List<String> summary = new List<String>();
summary.add('Username | Action');

for (User u : toDeactivate) {
    summary.add(u.Username + ' | Deactivated + Renamed (archived_' + ts + '_*)');
    toUpdate.add(new User(
        Id       = u.Id,
        IsActive = false,
        Username = 'archived_' + ts + '_' + u.Username
    ));
}

update toUpdate;

System.debug(LoggingLevel.INFO, '=== Demo User Delete Summary ===');
for (String line : summary) {
    System.debug(LoggingLevel.INFO, line);
}
System.debug(LoggingLevel.INFO, 'Revoked ' + psas.size() + ' PermissionSetAssignments.');
