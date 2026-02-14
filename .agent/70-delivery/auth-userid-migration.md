# Auth + user_id移行（最短プラン）

## 目的
- `LIFECAST_DEV_*` 固定ID依存を段階的に廃止する。
- 全APIを `request user_id` 基準で動かす。
- `creator` はロール（プロジェクト作成者）として扱い、IDモデルは `users.id` に統一する。

## 旧実装ホットスポット（要除去）
- `apps/backend/src/routes/discover.ts`
  - `resolveViewerUserId/resolveProfileUserIdForMe`（削除対象）
  - `/v1/me/*`, `/v1/creators/*/follow` の dev fallback
- `apps/backend/src/routes/projects.ts`
  - `/v1/me/project`, `/v1/me/projects`, create/delete/end が `LIFECAST_DEV_CREATOR_USER_ID` 依存
- `apps/backend/src/routes/uploads.ts`
  - `/v1/videos/mine`, `/v1/videos/:videoId DELETE` が `LIFECAST_DEV_CREATOR_USER_ID` 依存
- `apps/backend/src/store/services/supportsService.ts`
  - `prepareSupport` が `LIFECAST_DEV_VIEWER_USER_ID` fallback
- `apps/backend/src/store/services/uploadsService.ts`
  - `createUploadSession` が `LIFECAST_DEV_CREATOR_USER_ID` fallback

## フェーズ
1. Request Context統一（着手済み）
2. Routesを `req user_id` 必須へ移行（着手済み）
3. Service層の dev fallback排除（着手済み）
4. iOSクライアントが `x-lifecast-user-id` を送信（完了）
5. Auth API（Email/Password, Google, Apple）導入（完了）
6. OAuth callbackを iOS deep link で受けて token 保存（完了）
7. `LIFECAST_DEFAULT_USER_ID` と `LIFECAST_DEV_*` の完全撤去（次）
8. DB命名整備（`creator_user_id` カラムは互換維持しつつ概念を `user_id` へ寄せる）（次）

## 今回適用済み
- `apps/backend/src/auth/requestContext.ts` を追加
  - `x-lifecast-user-id` -> `req.lifecastAuth.userId`
  - fallback順: `LIFECAST_DEFAULT_USER_ID` -> legacy `LIFECAST_DEV_*`
  - `requireRequestUserId()` で未認証を `401` 返却
- `apps/backend/src/app.ts`
  - `onRequest` で auth context注入
- `apps/backend/src/routes/supports.ts`
  - prepare を request user基準へ
- `apps/backend/src/routes/uploads.ts`
  - create/list mine/delete を request user基準へ
- `apps/backend/src/routes/projects.ts`
  - `/v1/me/*` + create/delete/end を request user基準へ
- `apps/backend/src/routes/discover.ts`
  - me/follow系を request user基準へ
  - `LIFECAST_DEV_CREATOR_USER_ID` 比較 fallback を除去
- `apps/backend/src/store/services/supportsService.ts`
  - `prepareSupport` に `supporterUserId` を必須化
- `apps/backend/src/store/services/uploadsService.ts`
  - `createUploadSession` に `creatorUserId` を必須化
- `apps/backend/.env.example`
  - `LIFECAST_DEFAULT_USER_ID` 追加
  - `LIFECAST_DEV_*` を legacy/deprecated 明記
- `apps/backend/src/routes/auth.ts`
  - `POST /v1/auth/email/sign-up`
  - `POST /v1/auth/email/sign-in`
  - `POST /v1/auth/token/refresh`
  - `POST /v1/auth/sign-out`
  - `GET /v1/auth/oauth/url?provider=google|apple`
- `apps/backend/src/auth/requestContext.ts`
  - `Authorization: Bearer` から Supabase `/auth/v1/user` で `user_id` 解決
- `apps/ios/LifeCast/LifeCast/LifeCastAPIClient.swift`
  - email sign-in/sign-up/refresh/sign-out 実装
  - OAuth authorize URL 取得実装
  - deep link callback token 解析 (`lifecast://auth/callback`)
- `apps/ios/LifeCast/LifeCast/LifeCastApp.swift`
  - `onOpenURL` で OAuth callback 受信
- `apps/ios/LifeCast/LifeCast.xcodeproj/project.pbxproj`
  - URL scheme `lifecast` 登録

## 次の実装（この続き）
- `LIFECAST_DEFAULT_USER_ID` を使わない構成へ移行（未認証は常に401）。
- `LIFECAST_DEV_*` 参照を backend 全体で 0 件にする。
- dev switch UIは debug限定フラグに閉じる（本番ビルド除外）。
- Supabase OAuthを PKCE に切替（`response_type=token` 依存の解消）。
