# Google Play 課金ポリシー調査: クラウドファンディング・マーケットプレイスアプリ

調査日: 2026-02-14

---

## 1. クラウドファンディングプラットフォームにGoogle Play Billingは必要か？

### 結論: 基本的に不要（物理的リターンの場合）

Google Play の決済ポリシーにおいて、**Google Play Billing（アプリ内課金）が必要なのは「デジタル商品・サービスのアプリ内購入」のみ**である。

以下は **Google Play Billing が不要** な取引:
- **物理的商品の購入・レンタル**（食料品、衣類、家電、電子機器など）
- **物理的サービスの購入**（交通サービス、航空券、ジム会員、フードデリバリーなど）
- **P2P決済**（100%がクリエイターに渡り、デジタルコンテンツ・サービスへのアクセスを付与しない場合）

**クラウドファンディングの支援金は「物理的商品・サービスの購入」に分類される可能性が高い。** リターンが物理的な商品（グッズ、限定品等）やリアルな体験（イベント参加権等）である場合、Google Play Billingの利用は不要。

### 重要な例外
- リターンが**デジタルコンテンツ**（限定動画、デジタルバッジ、アプリ内特典等）の場合は、Google Play Billingが**必要**になる可能性がある
- ただし「consumption-only」アプリ（アプリ内で購入機能を持たないアプリ）として設計し、WebView/外部ブラウザで決済を完結させる方法もある

**参照ポリシー:**
- [Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- [Payments - Play Console Help](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)

---

## 2. クラウドファンディングアプリの分類と「マーケットプレイス」免除

### Google Play上の分類

Google Playは**クラウドファンディングアプリを独立したカテゴリとして明示的に定義していない**。代わりに、取引の性質（デジタル商品 vs 物理的商品）によって課金要件が決まる。

### 「マーケットプレイス」免除について

Google Playには Apple のような明示的な「マーケットプレイス免除」カテゴリは存在しない。しかし、以下の原則が適用される:

| 取引の性質 | Google Play Billing | 根拠 |
|-----------|-------------------|------|
| 物理的商品の購入 | 不要 | 物理的商品免除 |
| 物理的サービスの購入 | 不要 | 物理的サービス免除 |
| デジタル商品の購入 | 必要 | デジタル商品ポリシー |
| P2P送金（100%がクリエイターへ、デジタル特典なし） | 不要 | P2P決済免除 |
| 仮想通貨・コインの購入 | 必要 | デジタル商品に該当 |

### Consumption-Only アプリの選択肢

Google Playは**あらゆるアプリを「consumption-only」として認めている**。これは:
- アプリ内で商品・サービスの購入機能を持たない
- ユーザーは別の場所（Web等）で購入した商品・サービスをアプリ内で消費する
- 有料サービスの一部であっても、アプリ自体がconsumption-onlyであれば問題ない

**クラウドファンディングアプリとして、WebView経由で外部決済ページに遷移させる設計は、この「consumption-only」の考え方に近い運用が可能。**

---

## 3. 既存クラウドファンディングアプリの決済方法（Android）

### CAMPFIRE（日本）
- **Google Play Billingは使用していない**
- 独自の決済システムを使用（WebView/外部ブラウザ経由）
- 対応決済: クレジットカード、コンビニ払い、銀行振込、キャリア決済、PayPay、楽天ペイ、au PAY、FamiPay
- 理由: 支援金は物理的リターンに対する支払いであり、Google Play Billingの対象外

### Makuake（日本）
- **Google Play Billingは使用していない**
- 「応援購入」モデルで物理的商品・体験が中心
- 対応決済: クレジットカード、コンビニ払い、PayEasy銀行振込
- Google Playにアプリ公開中（[Play Store](https://play.google.com/store/apps/details?id=com.ca_crowdfunding.makuake_android)）

### Kickstarter（米国/グローバル）
- **Google Play Billingは使用していない**
- **Stripe**を決済基盤として使用（Stripe Payment Element）
- 支払いはStripeのホステッドコンポーネント経由で処理
- 対応決済: クレジット/デビットカード、各種デジタルウォレット
- Stripe導入により平均注文額が22%増加した実績あり

### GoFundMe（米国/グローバル）
- **Google Play Billingは使用していない**
- **Stripe**を決済基盤として使用
- 寄付型であり、物理的商品の売買ではないが、「税免除の寄付」ではないため独自決済を使用
- Google Playにアプリ公開中

### 共通パターン
**4社すべてがGoogle Play Billingを使用せず、独自の決済基盤（主にStripe）を利用している。** これは、クラウドファンディングの支援金が「デジタル商品のアプリ内購入」に該当しないためである。

---

## 4. Google Playの手数料体系（2025-2026年現在）

### 標準手数料率

| カテゴリ | 手数料率 | 条件 |
|---------|---------|------|
| 年間収益100万ドル以下 | **15%** | 要登録（Play Console内で減額プログラムに登録が必要） |
| 年間収益100万ドル超過分 | **30%** | 超過分に適用、年度ごとにリセット |
| 自動更新サブスクリプション | **15%** | 初日から15%（収益額に関係なく） |
| 音楽ストリーミング・電子書籍 | **10%** | Play Media Experience Program参加時 |

### 代替課金時の割引

| 地域/プログラム | 割引 | 結果 |
|---------------|------|------|
| User Choice Billing（日本含む） | **-4%** | 標準30% → 26%、15% → 11% |
| 韓国・インド（代替課金承認済み） | **-4%** | 同上 |
| 米国（Epic訴訟判決後） | **義務なし** | Google Play Billing自体が不要に |

### 日本市場 MSCA法適用後（2025年12月18日施行）

| 決済方式 | 手数料率 |
|---------|---------|
| Google Play Billing（標準） | 30%（100万ドル以下は15%） |
| アプリ内代替課金 | **26%**（標準から-4%） |
| 外部サイト誘導（アプリ外課金） | **20%** |
| 小規模開発者（100万ドル以下）+ 外部誘導 | **10%** |

### 重要な注意点
- **物理的商品・サービスの取引には手数料は一切かからない**
- 手数料はGoogle Play Billingを通じたデジタル商品の取引にのみ適用される
- 登録料: 初回25 USD（年間更新なし）

**参照:**
- [Service fees - Play Console Help](https://support.google.com/googleplay/android-developer/answer/112622?hl=en)
- [Google Play and App Store Fees 2025](https://splitmetrics.com/blog/google-play-apple-app-store-fees/)

---

## 5. User Choice Billing（UCB）とクラウドファンディングアプリ

### UCBの概要

User Choice Billing は、ユーザーがチェックアウト時にGoogle Play Billingとサードパーティ決済を選択できるプログラム。

### 日本での適用状況

- **2022年**: 日本を含む35カ国以上でパイロットプログラム開始
- **2025年12月18日**: MSCA法施行により、**全アプリカテゴリ**（ゲーム含む）に拡大
- 以前はゲーム以外のアプリに限定されていた制限が撤廃

### クラウドファンディングアプリへの適用

**UCBはデジタル商品の決済にのみ関連する。** クラウドファンディングアプリが物理的リターンの支援のみを扱う場合、そもそもGoogle Play Billingが不要なため、UCBの対象外。

ただし、以下の場合はUCBが関連する:
- デジタルリターン（限定動画、デジタルコンテンツ等）を提供する場合
- 仮想通貨/コインを使った投げ銭機能がある場合

**参照:**
- [Play User Choice Billing](https://play.google.com/console/about/programs/userchoicepilot/)
- [Understanding user choice billing](https://support.google.com/googleplay/android-developer/answer/13821247?hl=en)

---

## 6. ハイブリッドアプリ（クラウドファンディング + 投げ銭/寄付）の課金要件

### 機能別の課金要件

本プロジェクト「ショート動画 x クラウドファンディング + 投げ銭」に直接関連する分析:

| 機能 | Google Play Billing | 条件・根拠 |
|------|-------------------|-----------|
| クラファン支援（物理的リターン） | **不要** | 物理的商品免除 |
| クラファン支援（デジタルリターン） | **必要**（原則） | デジタル商品に該当 |
| 投げ銭（100%クリエイターへ、特典なし） | **不要** | P2P決済免除 |
| 投げ銭（プラットフォーム手数料あり） | **必要**（原則） | P2P免除の条件を満たさない |
| 投げ銭（仮想コイン購入型） | **必要** | 仮想通貨はデジタル商品 |
| 月額サブスクリプション | **必要** | デジタルサービスに該当 |

### P2P決済免除の詳細条件（投げ銭に重要）

Google Playは以下の**すべての条件**を満たす場合、P2P決済としてGoogle Play Billingを免除する:

1. **100%がクリエイターに渡る**（プラットフォーム手数料なし）
2. **デジタルコンテンツ・サービスへのアクセスを付与しない**（ステッカー、バッジ、特別な絵文字等を含む）

**いずれかの条件を満たさない場合、Google Play Billingの使用が必須。**

### TikTokの投げ銭モデルとの比較

TikTokは「コイン」（仮想通貨）を使った投げ銭モデル:
- **コインの購入にはGoogle Play Billingを使用**（65コイン=\$0.99 ~ 6,607コイン=\$99.99）
- コインは「デジタル商品」に分類される
- コインをギフトに変換してクリエイターに贈る仕組み
- クリエイターはギフトを「ダイヤモンド」に変換し、現金化

**つまり、コイン/仮想通貨ベースの投げ銭はGoogle Play Billingが必須。**

### 推奨設計パターン

**パターンA: 最大限の手数料回避**
```
クラファン支援（物理的リターン）→ 外部決済（Stripe等） → 手数料0%
投げ銭（100%クリエイターへ、特典なし）→ 外部決済 → 手数料0%
```
- メリット: Google手数料完全回避
- デメリット: プラットフォーム収益が投げ銭から得られない、デジタルリターン不可

**パターンB: ハイブリッド（推奨）**
```
クラファン支援（物理的リターン）→ 外部決済（Stripe等） → 手数料0%
投げ銭（コイン購入型）→ Google Play Billing → 手数料15-30%
デジタルリターン → Google Play Billing → 手数料15-30%
```
- メリット: プラットフォーム収益確保、多様なリターン対応
- デメリット: Google手数料が発生

**パターンC: MSCA活用（日本市場向け）**
```
クラファン支援（物理的リターン）→ 外部決済 → 手数料0%
投げ銭（コイン型）→ アプリ内代替課金 → 手数料26%（-4%割引）
  or → 外部サイト誘導 → 手数料20%
```

---

## 7. TikTok Shopの決済方式（Android）

### 概要

TikTok Shopは**物理的商品のECプラットフォーム**であり、Google Play Billingを使用していない。

### 決済方式
- クレジット/デビットカード（Visa、Mastercard、American Express、Discover）
- PayPal
- Google Pay（Android） ※Google Play Billingではなく、Google Payの決済API
- Klarna（4回分割払い）
- Affirm（月額分割払い）

### Google Play Billing不使用の理由
- TikTok Shopは**物理的商品の売買**であり、Google Playの「物理的商品免除」に該当
- Google Pay（決済手段）とGoogle Play Billing（課金システム）は別物
- TikTok Shop内の取引にはGoogleへの手数料は発生しない

### TikTokの二重構造
| 機能 | 決済方式 | Google手数料 |
|------|---------|-------------|
| TikTok Shop（物理商品購入） | 独自決済（Stripe/各種カード） | なし |
| TikTok コイン（仮想通貨） | Google Play Billing | 15-30% |
| TikTok ライブギフト | コイン経由 → Google Play Billing | 15-30% |

**この二重構造は、本プロジェクトのハイブリッドモデルの参考になる。**

---

## 8. 日本市場における最新動向（MSCA法）

### スマートフォンソフトウェア競争促進法（MSCA）

**施行日: 2025年12月18日**

日本の公正取引委員会が制定。Apple・Googleが「特定ソフトウェア事業者」に指定された。

### Google Playへの影響

| 変更点 | 詳細 |
|--------|------|
| 代替課金の全面開放 | 全アプリカテゴリ（ゲーム含む）で代替課金が可能に |
| 外部リンク許可 | アプリから外部決済ページへのリンクが可能 |
| 選択画面の表示 | ブラウザ・検索エンジンの選択画面を表示 |
| サードパーティストア | サードパーティアプリストアの許可 |

### 手数料の変化（デジタル商品の場合）

| 決済方式 | 従来 | MSCA後 |
|---------|------|--------|
| Google Play Billing | 30% | 30%（変更なし） |
| アプリ内代替課金 | N/A（不可） | 26%（-4%） |
| 外部サイト誘導 | N/A（不可） | 20%（-10%） |

### 本プロジェクトへの影響

MSCA法により、日本市場では:
1. **デジタルリターンや投げ銭のコイン購入でも、外部決済を選択肢として提供可能**
2. 外部サイト誘導なら手数料20%（標準30%から-10%）
3. アプリ内代替課金なら手数料26%（標準30%から-4%）
4. **ただしクラファン支援（物理的リターン）は元々手数料0%なので、MSCA法の恩恵は限定的**

**参照:**
- [スマホソフトウェア競争促進法への対応について（Google）](https://blog.google/intl/ja-jp/company-news/outreach-initiatives/complying-with-mobile-software-competition-act/)
- [スマートフォンソフトウェア競争促進法 | 公正取引委員会](https://www.jftc.go.jp/msca/)
- [Japan MSCA and mobile game developers](https://www.neonpay.com/blog/japans-mobile-software-competition-act-what-changed-for-mobile-game-developers)

---

## 9. 本プロジェクトへの戦略的提言

### Apple（別調査）との比較サマリー

| 項目 | Google Play | 備考 |
|------|------------|------|
| クラファン支援（物理リターン） | 外部決済OK、手数料0% | Appleも同様 |
| 投げ銭（P2P、100%クリエイター） | 外部決済OK、手数料0% | Appleも同様の免除あり |
| 投げ銭（コイン型） | Google Play Billing必要、15-30% | MSCA法で代替課金26%/外部20%も可 |
| デジタルリターン | Google Play Billing必要、15-30% | 同上 |
| 日本MSCA法 | 代替課金・外部誘導が全面解禁 | 2025年12月施行済み |

### 推奨アーキテクチャ

```
┌─────────────────────────────────────────────┐
│          ショート動画 x クラファン アプリ          │
├─────────────────┬───────────────────────────┤
│ クラファン支援    │ 外部決済（Stripe Connect）   │
│ (物理的リターン)  │ → Google手数料 0%           │
├─────────────────┼───────────────────────────┤
│ 投げ銭（直接型）  │ 外部決済（100%クリエイター）  │
│ P2P免除条件充足  │ → Google手数料 0%            │
├─────────────────┼───────────────────────────┤
│ 投げ銭（コイン型）│ MSCA代替課金 or 外部誘導     │
│ ※将来実装       │ → Google手数料 20-26%        │
├─────────────────┼───────────────────────────┤
│ プレミアム機能    │ Google Play Billing          │
│ ※将来実装       │ → Google手数料 15%           │
└─────────────────┴───────────────────────────┘
```

### 初期フェーズの推奨

1. **クラファン支援は外部決済（Stripe Connect）一択** — 物理的リターン前提で手数料0%
2. **投げ銭はP2P免除を活用** — 100%クリエイターに渡す設計で手数料0%（プラットフォーム収益は別の方法で確保）
3. **コイン型投げ銭やデジタルリターンは後期フェーズ** — Google手数料が発生するため、十分なユーザーベースができてから検討
4. **日本市場ではMSCA法を活用** — デジタル商品の決済でも外部誘導（20%）を選択可能

---

## 出典一覧

- [Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- [Payments - Play Console Help](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)
- [Service fees - Play Console Help](https://support.google.com/googleplay/android-developer/answer/112622?hl=en)
- [Developer Program Policy](https://support.google.com/googleplay/android-developer/answer/16549787?hl=en)
- [Play User Choice Billing](https://play.google.com/console/about/programs/userchoicepilot/)
- [Google Play billing FAQ (2020)](https://android-developers.googleblog.com/2020/09/commerce-update-faqs.html)
- [An update regarding Google Play's policies for US users](https://support.google.com/googleplay/android-developer/answer/15582165?hl=en)
- [Offering alternative billing in the US](https://support.google.com/googleplay/android-developer/answer/16497028?hl=en)
- [Google's MSCA compliance (Japan)](https://blog.google/intl/ja-jp/company-news/outreach-initiatives/complying-with-mobile-software-competition-act/)
- [JFTC MSCA page](https://www.jftc.go.jp/msca/)
- [Japan MSCA for mobile developers (Neon)](https://www.neonpay.com/blog/japans-mobile-software-competition-act-what-changed-for-mobile-game-developers)
- [Google Play and App Store Fees 2025](https://splitmetrics.com/blog/google-play-apple-app-store-fees/)
- [PAY.JP アプリ外課金解説](https://pay.jp/column/external-payment)
- [GIGAZINE MSCA報道](https://gigazine.net/gsc_news/en/20251218-msca-apple-google/)
- [Kickstarter x Stripe](https://stripe.com/customers/kickstarter)
- [GoFundMe x Stripe](https://stripe.com/newsroom/news/gofundme)
- [TikTok Shop payment methods](https://seller-us.tiktok.com/university/essay?knowledge_id=4186564050224897&lang=en)
