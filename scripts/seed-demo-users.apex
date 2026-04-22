// =============================================================================
// seed-demo-users.apex
//
// Idempotent demo-user seed for the RE CRM SDO.
//
// Email policy:
//   Email = Username (same .invalid TLD). RFC 2606 reserves .invalid as
//   guaranteed-non-deliverable, so welcome emails and subsequent notifications
//   bounce safely at the resolver. We do NOT set Email=null because Salesforce
//   rejects null Email on User insert. Welcome-email suppression is belt-and-
//   suspenders applied via Database.DMLOptions.emailHeader.triggerUserEmail=false.
//
// Idempotency:
//   Re-running this script produces no duplicate Users or duplicate
//   PermissionSetAssignments. Existing users (matched by Username) are left
//   untouched except for PSA reconciliation. Only newly-created users get a
//   password reset; the generated password is logged once.
//
// Failure modes:
//   If any RECRM_* role or RECRM_* permission set referenced below is missing,
//   the script throws SeedUsersException before any DML — fail loud, not silent.
//
// Run with:
//   sf apex run --file scripts/seed-demo-users.apex --target-org re-crm-sdo
// =============================================================================

public class SeedUsersException extends Exception {}

public class DemoUserSpec {
    public String username;
    public String firstName;
    public String lastName;
    public String alias;
    public String roleDevName;  // null for users without a role (Inventory Admin)
    public String permSetName;

    public DemoUserSpec(String username, String firstName, String lastName,
                       String alias, String roleDevName, String permSetName) {
        this.username = username;
        this.firstName = firstName;
        this.lastName = lastName;
        this.alias = alias;
        this.roleDevName = roleDevName;
        this.permSetName = permSetName;
    }
}

List<DemoUserSpec> specs = new List<DemoUserSpec>{
    new DemoUserSpec('rm.prk@recrm-demo.invalid',     'RM',        'PRK',     'rmprk',    'RECRM_RM_Team_PRK',     'RECRM_RM'),
    new DemoUserSpec('rm.spl@recrm-demo.invalid',     'RM',        'SPL',     'rmspl',    'RECRM_RM_Team_SPL',     'RECRM_RM'),
    new DemoUserSpec('psm.prk@recrm-demo.invalid',    'PSM',       'PRK',     'psmprk',   'RECRM_PSM_PRK',         'RECRM_PSM'),
    new DemoUserSpec('saleshead@recrm-demo.invalid',  'Sales',     'Head',    'saleshd',  'RECRM_Sales_Head',      'RECRM_Sales_Head'),
    new DemoUserSpec('postsales@recrm-demo.invalid',  'Post',      'Sales',   'postsale', 'RECRM_Post_Sales_Exec', 'RECRM_Post_Sales_Exec'),
    new DemoUserSpec('cpmgr@recrm-demo.invalid',      'CP',        'Manager', 'cpmgr',    'RECRM_CP_Manager',      'RECRM_CP_Manager'),
    new DemoUserSpec('invadmin@recrm-demo.invalid',   'Inventory', 'Admin',   'invadmin', null,                    'RECRM_Inventory_Admin')
};

// --- bulk lookups ---
Profile profile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];

Map<String, Id> roleIdByName = new Map<String, Id>();
for (UserRole r : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName LIKE 'RECRM_%']) {
    roleIdByName.put(r.DeveloperName, r.Id);
}

Map<String, Id> psIdByName = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name LIKE 'RECRM_%']) {
    psIdByName.put(ps.Name, ps.Id);
}

// --- validate all spec references before any DML ---
for (DemoUserSpec spec : specs) {
    if (spec.roleDevName != null && !roleIdByName.containsKey(spec.roleDevName)) {
        throw new SeedUsersException('Role not found: ' + spec.roleDevName +
            ' — did E03 roles deploy to this org?');
    }
    if (!psIdByName.containsKey(spec.permSetName)) {
        throw new SeedUsersException('PermissionSet not found: ' + spec.permSetName +
            ' — did E04 permission sets deploy to this org?');
    }
}

// --- welcome-email suppression ---
Database.DMLOptions dmlOpts = new Database.DMLOptions();
dmlOpts.EmailHeader.triggerUserEmail = false;

// --- process each spec ---
List<String> summary = new List<String>();
summary.add('Username | UserId | State | PSAssignment | TempPassword');

for (DemoUserSpec spec : specs) {
    List<User> existing = [
        SELECT Id, IsActive FROM User
        WHERE Username = :spec.username LIMIT 1
    ];

    Id userId;
    String state;
    String tempPassword = '(not reset — user pre-existed)';

    if (existing.isEmpty()) {
        User u = new User();
        u.Username           = spec.username;
        u.Email              = spec.username;  // .invalid TLD — safe
        u.FirstName          = spec.firstName;
        u.LastName           = spec.lastName;
        u.Alias              = spec.alias;
        u.CommunityNickname  = spec.alias + '_' + String.valueOf(System.now().getTime());
        u.ProfileId          = profile.Id;
        if (spec.roleDevName != null) {
            u.UserRoleId     = roleIdByName.get(spec.roleDevName);
        }
        u.LocaleSidKey                   = 'en_IN';
        u.TimeZoneSidKey                 = 'Asia/Kolkata';
        u.LanguageLocaleKey              = 'en_US';
        u.EmailEncodingKey               = 'UTF-8';
        u.UserPermissionsMarketingUser   = false;
        u.IsActive                       = true;

        Database.insert(u, dmlOpts);
        userId = u.Id;
        state = 'Created';

        // Reset password; sendUserEmail=false (RFC-safe email anyway, no notification wanted)
        System.ResetPasswordResult rpr = System.resetPassword(userId, false);
        tempPassword = rpr.getPassword();
    } else {
        userId = existing[0].Id;
        state = existing[0].IsActive ? 'Existing (active)' : 'Existing (re-activated)';
        if (!existing[0].IsActive) {
            update new User(Id = userId, IsActive = true);
        }
    }

    // Ensure permission-set assignment
    Id psId = psIdByName.get(spec.permSetName);
    List<PermissionSetAssignment> psas = [
        SELECT Id FROM PermissionSetAssignment
        WHERE AssigneeId = :userId AND PermissionSetId = :psId LIMIT 1
    ];
    String psAssignment = psas.isEmpty() ? 'Assigned (new)' : 'Already assigned';
    if (psas.isEmpty()) {
        insert new PermissionSetAssignment(
            AssigneeId       = userId,
            PermissionSetId  = psId
        );
    }

    summary.add(spec.username + ' | ' + userId + ' | ' + state +
                ' | ' + psAssignment + ' | ' + tempPassword);
}

System.debug(LoggingLevel.INFO, '=== Demo User Seed Summary ===');
for (String line : summary) {
    System.debug(LoggingLevel.INFO, line);
}
