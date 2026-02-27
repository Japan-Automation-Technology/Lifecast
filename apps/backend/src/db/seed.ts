import { dbPool, hasDb } from "../store/db.js";
import {
  DEV_ALT_CREATOR_USER_ID,
  DEV_ALT_PLAN_BASIC_ID,
  DEV_ALT_PLAN_PREMIUM_ID,
  DEV_ALT_PLAN_STANDARD_ID,
  DEV_ALT_PROJECT_ID,
  DEV_CREATOR_USER_ID,
  DEV_PLAN_BASIC_ID,
  DEV_PLAN_PREMIUM_ID,
  DEV_PLAN_STANDARD_ID,
  DEV_PROJECT_ID,
  DEV_REPORTER_USER_ID,
  DEV_SUPPORTER_USER_ID,
} from "./constants.js";

type ProjectSeed = {
  id: string;
  creatorUserId: string;
  title: string;
  subtitle: string;
  category: string;
  location: string;
  goalAmountMinor: number;
  durationDays: number;
  description: string;
  imageUrls: string[];
  urls: string[];
  detailBlocks: Array<
    | { type: "heading"; text: string }
    | { type: "text"; text: string }
    | { type: "quote"; text: string }
    | { type: "image"; image_url: string | null }
    | { type: "bullets"; items: string[] }
  >;
  plans: Array<{
    id: string;
    name: string;
    rewardSummary: string;
    description: string;
    imageUrl: string;
    priceMinor: number;
  }>;
  supportRows: Array<{
    id: string;
    supporterUserId: string;
    planId: string;
    amountMinor: number;
    checkoutSessionId: string;
  }>;
};

const EXTRA_CREATOR_1 = "00000000-0000-0000-0000-000000000005";
const EXTRA_CREATOR_2 = "00000000-0000-0000-0000-000000000006";
const EXTRA_SUPPORTER_1 = "00000000-0000-0000-0000-000000000011";
const EXTRA_SUPPORTER_2 = "00000000-0000-0000-0000-000000000012";
const EXTRA_SUPPORTER_3 = "00000000-0000-0000-0000-000000000013";

const projects: ProjectSeed[] = [
  {
    id: DEV_PROJECT_ID,
    creatorUserId: DEV_CREATOR_USER_ID,
    title: "FEDECA つかみのトング",
    subtitle: "分厚い肉を逃さず、置いても先端が触れない",
    category: "Kitchen",
    location: "Hyogo, Japan",
    goalAmountMinor: 300000,
    durationDays: 51,
    description: "累計6万本の実績から生まれた、ホールド力重視の新作トング。",
    imageUrls: [
      "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1467003909585-2f8a72700288?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1528715471579-d1bcf0ba5e83?auto=format&fit=crop&w=1600&q=80",
    ],
    urls: ["https://lifecast.jp/projects/fedeca-tongs"],
    detailBlocks: [
      { type: "heading", text: "ストーリー" },
      { type: "text", text: "分厚い肉をつかんだ瞬間に分かる、しっかりしたホールド感を追求しました。" },
      { type: "bullets", items: ["先端が触れにくい自立バランス", "耐熱・耐久を意識した仕上げ", "毎日使える重量感"] },
      { type: "image", image_url: "https://images.unsplash.com/photo-1467003909585-2f8a72700288?auto=format&fit=crop&w=1600&q=80" },
      { type: "quote", text: "つかみやすさと置きやすさ、両方に妥協しない道具を作りました。" },
    ],
    plans: [
      {
        id: DEV_PLAN_BASIC_ID,
        name: "Early Support",
        rewardSummary: "先行生産ロット + 活動アップデート",
        description: "最速で受け取りたい方向けの基本プラン",
        imageUrl: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 3000,
      },
      {
        id: DEV_PLAN_STANDARD_ID,
        name: "Dual Set",
        rewardSummary: "2本セット + サポーターカード",
        description: "家庭用とアウトドア用で使い分けたい方向け",
        imageUrl: "https://images.unsplash.com/photo-1528715471579-d1bcf0ba5e83?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 6000,
      },
      {
        id: DEV_PLAN_PREMIUM_ID,
        name: "Workshop Visit",
        rewardSummary: "限定仕上げ + 工房見学枠",
        description: "開発背景まで体験できる限定プラン",
        imageUrl: "https://images.unsplash.com/photo-1467003909585-2f8a72700288?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 18000,
      },
    ],
    supportRows: [
      {
        id: "33333333-3333-3333-3333-333333333301",
        supporterUserId: DEV_SUPPORTER_USER_ID,
        planId: DEV_PLAN_PREMIUM_ID,
        amountMinor: 18000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444301",
      },
      {
        id: "33333333-3333-3333-3333-333333333302",
        supporterUserId: EXTRA_SUPPORTER_1,
        planId: DEV_PLAN_STANDARD_ID,
        amountMinor: 6000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444302",
      },
      {
        id: "33333333-3333-3333-3333-333333333303",
        supporterUserId: EXTRA_SUPPORTER_2,
        planId: DEV_PLAN_STANDARD_ID,
        amountMinor: 6000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444303",
      },
      {
        id: "33333333-3333-3333-3333-333333333304",
        supporterUserId: EXTRA_SUPPORTER_3,
        planId: DEV_PLAN_BASIC_ID,
        amountMinor: 3000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444304",
      },
    ],
  },
  {
    id: DEV_ALT_PROJECT_ID,
    creatorUserId: DEV_ALT_CREATOR_USER_ID,
    title: "Pocket Pixel Board v3",
    subtitle: "机の上で遊べるミニLEDゲームボード",
    category: "Game Hardware",
    location: "Tokyo, Japan",
    goalAmountMinor: 850000,
    durationDays: 34,
    description: "支持者の声をもとに、発色と耐久性を全面アップデート。",
    imageUrls: [
      "https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1542751371-adc38448a05e?auto=format&fit=crop&w=1600&q=80",
    ],
    urls: ["https://lifecast.jp/projects/pocket-pixel-board"],
    detailBlocks: [
      { type: "heading", text: "アップデート内容" },
      { type: "bullets", items: ["LED輝度 1.8倍", "USB-C給電の安定化", "ケース素材を高耐久化"] },
      { type: "image", image_url: "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=1600&q=80" },
      { type: "text", text: "試作機テストを3回実施し、落下耐性と発熱バランスを調整しました。" },
      { type: "quote", text: "遊び道具は、毎日触っても壊れないことが正義。" },
    ],
    plans: [
      {
        id: DEV_ALT_PLAN_BASIC_ID,
        name: "Starter",
        rewardSummary: "本体1台 + ロゴステッカー",
        description: "最小構成の応援プラン",
        imageUrl: "https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 5000,
      },
      {
        id: DEV_ALT_PLAN_STANDARD_ID,
        name: "Color Pack",
        rewardSummary: "本体 + 交換シェル3色",
        description: "外装カスタムを楽しみたい方向け",
        imageUrl: "https://images.unsplash.com/photo-1542751371-adc38448a05e?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 8200,
      },
      {
        id: DEV_ALT_PLAN_PREMIUM_ID,
        name: "Maker Edition",
        rewardSummary: "限定刻印 + 開発ノートPDF",
        description: "初期開発ストーリー付き限定版",
        imageUrl: "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 13000,
      },
    ],
    supportRows: [
      {
        id: "33333333-3333-3333-3333-333333333311",
        supporterUserId: DEV_SUPPORTER_USER_ID,
        planId: DEV_ALT_PLAN_STANDARD_ID,
        amountMinor: 8200,
        checkoutSessionId: "44444444-4444-4444-4444-444444444311",
      },
      {
        id: "33333333-3333-3333-3333-333333333312",
        supporterUserId: EXTRA_SUPPORTER_1,
        planId: DEV_ALT_PLAN_PREMIUM_ID,
        amountMinor: 13000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444312",
      },
    ],
  },
  {
    id: "11111111-1111-1111-1111-111111111115",
    creatorUserId: EXTRA_CREATOR_1,
    title: "Trail Pot Mini",
    subtitle: "キャンプ飯が捗る軽量クッカー",
    category: "Outdoor",
    location: "Nagano, Japan",
    goalAmountMinor: 420000,
    durationDays: 27,
    description: "軽量性と洗いやすさを両立したミニポットの新試作。",
    imageUrls: [
      "https://images.unsplash.com/photo-1523987355523-c7b5b84d7d58?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1504851149312-7a075b496cc7?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1470246973918-29a93221c455?auto=format&fit=crop&w=1600&q=80",
    ],
    urls: ["https://lifecast.jp/projects/trail-pot-mini"],
    detailBlocks: [
      { type: "heading", text: "目指す体験" },
      { type: "text", text: "湯沸かし・煮込み・取り分けを一つでこなせる道具を目指しています。" },
      { type: "image", image_url: "https://images.unsplash.com/photo-1470246973918-29a93221c455?auto=format&fit=crop&w=1600&q=80" },
      { type: "bullets", items: ["約320gの軽量設計", "内側セラミックで汚れ落ち良好", "収納しやすい折りたたみハンドル"] },
    ],
    plans: [
      {
        id: "22222222-2222-2222-2222-222222222227",
        name: "Solo Kit",
        rewardSummary: "本体 + 収納ポーチ",
        description: "ソロキャンプ向けの基本構成",
        imageUrl: "https://images.unsplash.com/photo-1523987355523-c7b5b84d7d58?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 4800,
      },
      {
        id: "22222222-2222-2222-2222-222222222228",
        name: "Camp Duo",
        rewardSummary: "本体2個 + 限定カラー",
        description: "ペア利用向けセット",
        imageUrl: "https://images.unsplash.com/photo-1504851149312-7a075b496cc7?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 9000,
      },
    ],
    supportRows: [
      {
        id: "33333333-3333-3333-3333-333333333321",
        supporterUserId: EXTRA_SUPPORTER_2,
        planId: "22222222-2222-2222-2222-222222222227",
        amountMinor: 4800,
        checkoutSessionId: "44444444-4444-4444-4444-444444444321",
      },
      {
        id: "33333333-3333-3333-3333-333333333322",
        supporterUserId: DEV_SUPPORTER_USER_ID,
        planId: "22222222-2222-2222-2222-222222222228",
        amountMinor: 9000,
        checkoutSessionId: "44444444-4444-4444-4444-444444444322",
      },
    ],
  },
  {
    id: "11111111-1111-1111-1111-111111111116",
    creatorUserId: EXTRA_CREATOR_2,
    title: "Desk Rail Light",
    subtitle: "作業動画が映える可動式ライト",
    category: "Creator Gear",
    location: "Fukuoka, Japan",
    goalAmountMinor: 760000,
    durationDays: 40,
    description: "撮影・配信・作業の3用途を一台でこなすデスクライト。",
    imageUrls: [
      "https://images.unsplash.com/photo-1516117172878-fd2c41f4a759?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=1600&q=80",
      "https://images.unsplash.com/photo-1493666438817-866a91353ca9?auto=format&fit=crop&w=1600&q=80",
    ],
    urls: ["https://lifecast.jp/projects/desk-rail-light"],
    detailBlocks: [
      { type: "heading", text: "使い方の幅" },
      { type: "bullets", items: ["真上から手元を照らす", "背景ライトとして使う", "縦動画向けの側面照明"] },
      { type: "quote", text: "ライト一つで撮影の見え方は劇的に変わる。" },
      { type: "image", image_url: "https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=1600&q=80" },
      { type: "text", text: "可動アームは300回以上の連続テストを行い、緩みにくい構造に改善しました。" },
    ],
    plans: [
      {
        id: "22222222-2222-2222-2222-222222222229",
        name: "Light Only",
        rewardSummary: "本体 + 交換用拡散フィルタ",
        description: "まずはライト単体で試したい方向け",
        imageUrl: "https://images.unsplash.com/photo-1493666438817-866a91353ca9?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 6800,
      },
      {
        id: "22222222-2222-2222-2222-222222222230",
        name: "Creator Bundle",
        rewardSummary: "ライト + スマホホルダー + 専用ケーブル",
        description: "撮影セット込みの人気プラン",
        imageUrl: "https://images.unsplash.com/photo-1516117172878-fd2c41f4a759?auto=format&fit=crop&w=1200&q=80",
        priceMinor: 9800,
      },
    ],
    supportRows: [
      {
        id: "33333333-3333-3333-3333-333333333331",
        supporterUserId: EXTRA_SUPPORTER_1,
        planId: "22222222-2222-2222-2222-222222222230",
        amountMinor: 9800,
        checkoutSessionId: "44444444-4444-4444-4444-444444444331",
      },
      {
        id: "33333333-3333-3333-3333-333333333332",
        supporterUserId: EXTRA_SUPPORTER_3,
        planId: "22222222-2222-2222-2222-222222222229",
        amountMinor: 6800,
        checkoutSessionId: "44444444-4444-4444-4444-444444444332",
      },
    ],
  },
];

async function runSeed() {
  if (!hasDb() || !dbPool) {
    throw new Error("LIFECAST_DATABASE_URL is required for seed");
  }

  const client = await dbPool.connect();
  try {
    await client.query("begin");

    const allUserIds = [
      DEV_SUPPORTER_USER_ID,
      DEV_CREATOR_USER_ID,
      DEV_REPORTER_USER_ID,
      DEV_ALT_CREATOR_USER_ID,
      EXTRA_CREATOR_1,
      EXTRA_CREATOR_2,
      EXTRA_SUPPORTER_1,
      EXTRA_SUPPORTER_2,
      EXTRA_SUPPORTER_3,
    ];
    await client.query(
      `
      insert into users (id, created_at)
      select id::uuid, now() from unnest($1::text[]) as t(id)
      on conflict (id) do nothing
    `,
      [allUserIds],
    );

    await client.query(
      `
      create table if not exists creator_profiles (
        creator_user_id uuid primary key references users(id) on delete cascade,
        username text not null unique,
        display_name text,
        bio text,
        avatar_url text,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )
    `,
    );

    await client.query(
      `
      insert into creator_profiles (creator_user_id, username, display_name, bio, created_at, updated_at)
      values
        ($1, 'lifecast_maker', 'Lifecast Maker', 'Building products in public.', now(), now()),
        ($2, 'tak_game_lab', 'Tak Game Lab', 'Handheld game hardware development.', now(), now()),
        ($3, 'maker_arcade', 'Maker Arcade', 'Daily prototyping for creator tools.', now(), now()),
        ($4, 'craft_loop_lab', 'Craft Loop Lab', 'Small-batch gadgets for creative workflows.', now(), now())
      on conflict (creator_user_id)
      do update set
        username = excluded.username,
        display_name = excluded.display_name,
        bio = excluded.bio,
        updated_at = now()
    `,
      [DEV_CREATOR_USER_ID, DEV_ALT_CREATOR_USER_ID, EXTRA_CREATOR_1, EXTRA_CREATOR_2],
    );

    const projectIds = projects.map((project) => project.id);
    const creatorIds = Array.from(new Set(projects.map((project) => project.creatorUserId)));
    await client.query(
      `
      update projects
      set status = 'stopped',
          updated_at = now()
      where creator_user_id = any($1::uuid[])
        and status in ('active', 'draft')
        and id <> all($2::uuid[])
    `,
      [creatorIds, projectIds],
    );
    const seededSupportIds = projects.flatMap((project) => project.supportRows.map((support) => support.id));
    await client.query(
      `
      update support_transactions
      set status = 'failed',
          succeeded_at = null,
          updated_at = now()
      where project_id = any($1::uuid[])
        and status = 'succeeded'
        and id <> all($2::uuid[])
    `,
      [projectIds, seededSupportIds],
    );

    for (const project of projects) {
      const deadlineAt = new Date(Date.now() + project.durationDays * 24 * 60 * 60 * 1000).toISOString();
      await client.query(
        `
        insert into projects (
          id, creator_user_id, title, subtitle, cover_image_url, project_image_urls, project_detail_blocks, category, location,
          status, goal_amount_minor, currency, duration_days, deadline_at, description, external_urls, created_at, updated_at
        )
        values (
          $1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9,
          'active', $10, 'JPY', $11, $12, $13, $14::jsonb, now(), now()
        )
        on conflict (id)
        do update set
          creator_user_id = excluded.creator_user_id,
          title = excluded.title,
          subtitle = excluded.subtitle,
          cover_image_url = excluded.cover_image_url,
          project_image_urls = excluded.project_image_urls,
          project_detail_blocks = excluded.project_detail_blocks,
          category = excluded.category,
          location = excluded.location,
          status = excluded.status,
          goal_amount_minor = excluded.goal_amount_minor,
          currency = excluded.currency,
          duration_days = excluded.duration_days,
          deadline_at = excluded.deadline_at,
          description = excluded.description,
          external_urls = excluded.external_urls,
          updated_at = now()
      `,
        [
          project.id,
          project.creatorUserId,
          project.title,
          project.subtitle,
          project.imageUrls[0] ?? null,
          JSON.stringify(project.imageUrls),
          JSON.stringify(project.detailBlocks),
          project.category,
          project.location,
          project.goalAmountMinor,
          project.durationDays,
          deadlineAt,
          project.description,
          JSON.stringify(project.urls),
        ],
      );

      for (const plan of project.plans) {
        await client.query(
          `
          insert into project_plans (
            id, project_id, name, reward_summary, description, image_url, is_physical_reward, price_minor, currency, created_at, updated_at
          )
          values ($1, $2, $3, $4, $5, $6, true, $7, 'JPY', now(), now())
          on conflict (id)
          do update set
            project_id = excluded.project_id,
            name = excluded.name,
            reward_summary = excluded.reward_summary,
            description = excluded.description,
            image_url = excluded.image_url,
            is_physical_reward = excluded.is_physical_reward,
            price_minor = excluded.price_minor,
            currency = excluded.currency,
            updated_at = now()
        `,
          [plan.id, project.id, plan.name, plan.rewardSummary, plan.description, plan.imageUrl, plan.priceMinor],
        );
      }

      for (const support of project.supportRows) {
        await client.query(
          `
          insert into support_transactions (
            id, project_id, plan_id, supporter_user_id, amount_minor, currency, status, reward_type, cancellation_window_hours,
            provider, provider_checkout_session_id, prepared_at, confirmed_at, succeeded_at, created_at, updated_at
          )
          values (
            $1, $2, $3, $4, $5, 'JPY', 'succeeded', 'physical', 48,
            'stripe', $6, now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now()
          )
          on conflict (id) do nothing
        `,
          [support.id, project.id, support.planId, support.supporterUserId, support.amountMinor, support.checkoutSessionId],
        );
      }
    }

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
