import type { Metadata } from "next";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Dear Minowa-san | Lifecast",
  description:
    "投資家・箕輪厚介さんへ。Lifecastが求められる理由、関わってほしい理由、そして私たちがやるべき理由をまとめたページ。"
};

const whyNowItems = [
  {
    title: "1. ショート動画のプロセスエコノミー",
    body: "フォローして応援する行動は、すでに習慣化しています。次に必要なのは、明確なゴールに向かって進む体験です。単発の投げ銭ではなく、到達点を持つ支援モデルが機能します。"
  },
  {
    title: "2. 人間性への回帰",
    body: "いまは『何を作るか』だけでなく『誰が作るか』が選ばれる時代です。開発者の人格や信念が伝わるほど、支援は生まれやすくなります。"
  },
  {
    title: "3. アルゴリズム寡占",
    body: "発見の入り口はショート動画に集中しています。見つけてもらえる場所が限られる以上、ショート動画起点で資金調達まで完結する導線が必要です。"
  },
  {
    title: "4. 推し活文化の本格化",
    body: "人は推しにお金を使います。それは単なる消費ではなく、自己表現と自己実現の一部だからです。だからこそ『応援行為』を設計できるプロダクトが強い。"
  }
];

const researchFacts = [
  "SNS経由でクラファンを発見する比率は55%（research/phase3_agent_i_backer_behavior.md）",
  "動画ありキャンペーンは成功率が高い傾向（research/phase3_summary.md）",
  "既存CFの課題は発見・集客・制作負荷の分断（research/phase3_agent_j_pain_points.md）",
  "ショート動画市場と購入型CF市場の交差領域は拡大基調（research/phase2_agent_h_market_size.md）"
];

const whyMinowaItems = [
  "社会や人間に対する解像度が高く、時代の空気を言語化できる。",
  "個人的に強くリスペクトしており、継続的に発信を見て学んできた。",
  "短期ではなく、長期で事業と思想の両面に関わってほしい。",
  "経営者・投資家・クリエイターを横断する人脈があり、事業の初速を作れる。"
];

const whyUsItems = [
  "自分たちでクラファンをやろうとして、現行UXの課題を当事者として痛感した（Laplaceというボードゲーム企画）。",
  "AIを中心とした最新技術との親和性が高く、制作・運営の効率化を実践してきた（Singular Radio運営）。",
  "海外大生として、国内最適に閉じないグローバル志向でプロダクトを設計できる。"
];

export default function DearMinowaPage() {
  return (
    <main className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.kicker}>Dear Minowa-san</p>
        <h1>箕輪厚介さんへ</h1>
        <p>
          Lifecastは、ショート動画時代に最適化された購入型クラウドファンディングを作ろうとしています。
          これは、資金調達プロダクトというより「応援のOS」を作る挑戦です。
        </p>
      </section>

      <section className={styles.section}>
        <h2>なぜ、いまLifecastが求められるのか</h2>
        <div className={styles.grid}>
          {whyNowItems.map((item) => (
            <article key={item.title} className={styles.card}>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
        <ul className={styles.facts}>
          {researchFacts.map((fact) => (
            <li key={fact}>{fact}</li>
          ))}
        </ul>
      </section>

      <section className={styles.section}>
        <h2>なぜ、箕輪さんに関わってほしいのか</h2>
        <ul className={styles.list}>
          {whyMinowaItems.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </section>

      <section className={styles.section}>
        <h2>なぜ、私たちであるべきか</h2>
        <ul className={styles.list}>
          {whyUsItems.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </section>

      <section className={styles.closing}>
        <h2>最後に</h2>
        <p>
          もし一度お時間をいただけるなら、プロダクトの実画面と事業構想を10分でお見せします。
          応援が経済行動の中心になる時代に、次の当たり前を一緒に作りたいです。
        </p>
      </section>
    </main>
  );
}
