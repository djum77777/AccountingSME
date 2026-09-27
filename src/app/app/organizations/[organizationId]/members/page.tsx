import {
  activateMember,
  changeMemberRole,
  deactivateMember,
  inviteMember,
} from "@/app/actions/members";
import { getOrganizationMembers } from "@/data/organizations";
import { membershipRoles } from "@/lib/domain/access";
import { getTranslations } from "@/lib/i18n/server";

export default async function MembersPage({
  params,
}: {
  params: Promise<{ organizationId: string }>;
}) {
  const { organizationId } = await params;
  const [t, organizationData] = await Promise.all([
    getTranslations(),
    getOrganizationMembers(organizationId),
  ]);
  const { organization, memberships, activeSeatLimit } = organizationData;
  const activeCount = memberships.filter(
    (item) => item.status === "active",
  ).length;

  return (
    <section>
      <div className="section-heading">
        <div>
          <p className="eyebrow">{organization.baseCurrencyCode}</p>
          <h1>{organization.displayName}</h1>
        </div>
        <span className="seat-counter">
          {activeCount}/{activeSeatLimit} active seats
        </span>
      </div>
      <div className="members-layout">
        <div className="card table-card">
          <h2>{t.members}</h2>
          <div className="member-list">
            {memberships.map((membership) => (
              <article className="member-row" key={membership.id}>
                <div>
                  <strong>{membership.email}</strong>
                  <p>
                    {membership.role} · {membership.status}
                  </p>
                </div>
                <div className="member-actions">
                  {membership.status !== "active" ? (
                    <form action={activateMember}>
                      <input
                        name="organizationId"
                        type="hidden"
                        value={organizationId}
                      />
                      <input
                        name="membershipId"
                        type="hidden"
                        value={membership.id}
                      />
                      <button className="text-button" type="submit">
                        Activate
                      </button>
                    </form>
                  ) : (
                    <form action={deactivateMember}>
                      <input
                        name="organizationId"
                        type="hidden"
                        value={organizationId}
                      />
                      <input
                        name="membershipId"
                        type="hidden"
                        value={membership.id}
                      />
                      <button className="text-button danger" type="submit">
                        Deactivate
                      </button>
                    </form>
                  )}
                  <form action={changeMemberRole} className="inline-form">
                    <input
                      name="organizationId"
                      type="hidden"
                      value={organizationId}
                    />
                    <input
                      name="membershipId"
                      type="hidden"
                      value={membership.id}
                    />
                    <select
                      aria-label="Role"
                      defaultValue={membership.role}
                      name="role"
                    >
                      {membershipRoles.map((role) => (
                        <option key={role} value={role}>
                          {role}
                        </option>
                      ))}
                    </select>
                    <button className="text-button" type="submit">
                      Approve role
                    </button>
                  </form>
                </div>
              </article>
            ))}
          </div>
        </div>
        <aside className="card invite-card">
          <h2>{t.inviteMember}</h2>
          <form action={inviteMember}>
            <input name="organizationId" type="hidden" value={organizationId} />
            <label>
              {t.email}
              <input name="email" required type="email" />
            </label>
            <label>
              {t.role}
              <select defaultValue="staff" name="role">
                {membershipRoles.map((role) => (
                  <option key={role} value={role}>
                    {role}
                  </option>
                ))}
              </select>
            </label>
            <button className="button primary full" type="submit">
              {t.inviteMember}
            </button>
          </form>
          <p className="fine-print">
            Invitations do not consume a seat. Owner approval activates a member
            only when the organization has an entitled seat.
          </p>
        </aside>
      </div>
    </section>
  );
}
