import { dbPool, hasDb } from "../store/db.js";
import {
  DEV_CREATOR_USER_ID,
  DEV_PLAN_BASIC_ID,
  DEV_PLAN_PREMIUM_ID,
  DEV_PLAN_STANDARD_ID,
  DEV_PROJECT_ID,
  DEV_REPORTER_USER_ID,
  DEV_SUPPORTER_USER_ID,
} from "./constants.js";

async function runSeed() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required for seed");
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    await client.query(
      `
      insert into users (id, created_at)
      values ($1, now()), ($2, now()), ($3, now())
      on conflict (id) do nothing
    `,
      [DEV_SUPPORTER_USER_ID, DEV_CREATOR_USER_ID, DEV_REPORTER_USER_ID],
    );

    await client.query(
      `
      insert into projects (
        id, creator_user_id, title, status, goal_amount_minor, currency, deadline_at, created_at, updated_at
      )
      values (
        $1, $2, 'LifeCast Dev Project', 'active', 500000, 'JPY', now() + interval '14 days', now(), now()
      )
      on conflict (id)
      do update set
        creator_user_id = excluded.creator_user_id,
        title = excluded.title,
        status = excluded.status,
        goal_amount_minor = excluded.goal_amount_minor,
        currency = excluded.currency,
        deadline_at = excluded.deadline_at,
        updated_at = now()
    `,
      [DEV_PROJECT_ID, DEV_CREATOR_USER_ID],
    );

    await client.query(
      `
      insert into project_plans (
        id, project_id, name, reward_summary, is_physical_reward, price_minor, currency, created_at, updated_at
      )
      values
        ($1, $4, 'Basic', 'Sticker + progress updates', true, 1000, 'JPY', now(), now()),
        ($2, $4, 'Standard', 'T-shirt + early shipment', true, 3000, 'JPY', now(), now()),
        ($3, $4, 'Premium', 'Limited bundle', true, 8000, 'JPY', now(), now())
      on conflict (id)
      do update set
        project_id = excluded.project_id,
        name = excluded.name,
        reward_summary = excluded.reward_summary,
        is_physical_reward = excluded.is_physical_reward,
        price_minor = excluded.price_minor,
        currency = excluded.currency,
        updated_at = now()
    `,
      [DEV_PLAN_BASIC_ID, DEV_PLAN_STANDARD_ID, DEV_PLAN_PREMIUM_ID, DEV_PROJECT_ID],
    );

    await client.query("commit");

    console.log("[seed] done");
    console.log(`LIFECAST_DEV_SUPPORTER_USER_ID=${DEV_SUPPORTER_USER_ID}`);
    console.log(`LIFECAST_DEV_CREATOR_USER_ID=${DEV_CREATOR_USER_ID}`);
    console.log(`LIFECAST_DEV_REPORTER_USER_ID=${DEV_REPORTER_USER_ID}`);
    console.log(`DEV_PROJECT_ID=${DEV_PROJECT_ID}`);
    console.log(`DEV_PLAN_BASIC_ID=${DEV_PLAN_BASIC_ID}`);
    console.log(`DEV_PLAN_STANDARD_ID=${DEV_PLAN_STANDARD_ID}`);
    console.log(`DEV_PLAN_PREMIUM_ID=${DEV_PLAN_PREMIUM_ID}`);
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

runSeed()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("[seed] failed", error);
    process.exit(1);
  });
