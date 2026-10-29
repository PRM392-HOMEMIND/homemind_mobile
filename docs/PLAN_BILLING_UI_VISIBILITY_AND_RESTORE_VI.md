# Ẩn và khôi phục đường vào Gói & thanh toán

## Tổng quan và phạm vi

Trạng thái của bản này: **UI/navigation OFF** cho mọi Flutter platform và build. Giữ màn Billing/Paywall cùng business components để bật lại. Không sửa backend, API, database/migration, giá, entitlement, quota, thời hạn, webhook, đối soát hoặc dữ liệu lịch sử. Không bật thanh toán. Đây là policy client, không phải bảo mật API/server.

Tên gói và hạn mức đang dùng vẫn lấy từ HomeSummary/UserProfile/VoiceQuota hiện hữu. Cá nhân vẫn có thông tin gói, thẻ lượt, tổng/đã dùng/còn lại, progress bar, thời điểm làm mới và giải thích tại chỗ. VoiceQuotaPanel/BillingUsageCard và các service lấy dữ liệu không bị sửa. Những hàng Tên/điện thoại/địa chỉ/ngôn ngữ vẫn chỉnh sửa như cũ.

## Cờ tập trung

- Symbol: `PlanBillingVisibility.defaultVisible = false`.
- File: `lib/core/config/plan_billing_visibility.dart`.
- Getter cho UI: `PlanBillingVisibility.of(context)`; mọi điểm vào đọc cùng policy.
- `HomeMindApp` cung cấp scope mặc định ở MaterialApp.builder, kèm fallback builder đến auth/shell hiện hữu.
- Đây là **constant Flutter source**, không Dart define, remote flag, query parameter, preference hoặc endpoint. Android hiện chỉ cho hai application defines BACKEND_BASE_URL/APP_DISTRIBUTION; giữ nguyên allowlist đó và không tạo cấu hình chồng lấn.
- Store/direct, debug/profile/release, Android/iOS/Flutter web cùng mặc định false. Thiếu/malformed cấu hình hoặc URL `?SHOW_PLAN_AND_BILLING_UI=true` không thể bật lại.
- Test có thể inject `PlanBillingVisibility(visible:true, child:...)` để kiểm chứng trạng thái khôi phục. Production chỉ dùng scope mặc định, không đọc giá trị scope từ client input/API.
- Cờ này độc lập `EnvConfig.externalBillingAllowed` và checkoutEnabled. Bật lại UI không bật PayOS/mua gói, không đổi quyền lợi/quota.

## Kiểm kê các đường vào thật

Đường dẫn trong bảng tính từ `apps/homemind_mobile/`. Cách khôi phục chung: đổi defaultVisible thành true, rebuild; không viết lại nghiệp vụ.

| ID | Vị trí / nhãn cũ | File / symbol | Trước | Đã tắt và hiện tại | Khôi phục / test |
|---|---|---|---|---|---|
| P01 | Cá nhân → Thông tin chi tiết → Gói của bạn / Xem gói hiện tại | `lib/features/home/presentation/profile_page.dart`, ProfilePage, `_InfoRow`, profile_row_plan/profile_upgrade | Free có badge; free hoặc BillingSource có row onTap/chevron → PaywallSheet.show | onTap=null, trailing=null; `_InfoRow` trả Padding thuần, không InkWell/gesture/chevron/ripple/button semantics; giữ tên gói dữ liệu | Cờ true khôi phục nhánh cũ; read-only profile + restored scope tests |
| P02 | Trang chủ → PlanCard miễn phí / Xem gói hiện tại | `.../home/presentation/plan_card.dart`, PlanCard._free, plan_card_cta | CTA outlined/elevated → PaywallSheet.show | Loại cả CTA và spacing của CTA; giữ title, mức dùng, bar và giải thích | Cờ true; card warning và plan_card_test |
| P03 | PlanCard personal → Nâng lên Gia đình | cùng file, _paid, plan_card_family | Chỉ có khi external billing allowed + đúng plan | Kèm UI visibility; không render khi UI tắt | Cờ true khôi phục điều kiện gốc, không bật external billing; existing paid-plan contracts |
| P04 | PlanCard requested → Đổi gói | cùng file, _requested/plan_card_change | Chỉ có khi external billing allowed | Cả nhánh CTA nằm sau UI policy; nhánh không hoạt động dưới payment-off hiện tại được giữ nguyên | Cờ true, nguyên điều kiện gốc; plan_card_test |
| P05 | Tủ đồ → banner Gói miễn phí sắp đầy / Xem gói hiện tại | `.../inventory/presentation/inventory_page.dart`, _planBanner → `.../home/presentation/plan_card.dart`, PlanNudgeBanner | TextButton → PaywallSheet.show | PlanNudgeBanner không dựng action button khi UI tắt; warning/giới hạn vẫn đọc được | Cờ true; card and inventory warning test |
| P06 | Xác nhận inventory.add khi full free / Xem gói hiện tại | `.../assistant/presentation/confirm_page.dart`, _bottomBarFor/_confirm/_limitBanner | Nút mở Paywall hoặc mở tự động khi server PLAN_LIMIT | Loại cả CTA và spacing của CTA, giữ Huỷ + warning; không placeholder disabled; chặn cả đường server-error; warning không hướng dẫn nâng cấp | Cờ true khôi phục hành vi cũ; confirm block + plan_limit_test |
| P07 | Mic hết lượt → snackbar Xem gói hiện tại | `lib/app/app_shell.dart`, _openVoiceSheet | Free/personal có SnackBarAction → PaywallSheet.show | Action không render; giữ thông báo hết lượt; không mở STT khi quota=0 | Cờ true; voice exhausted + voice_quota_test |
| P08 | Search shortcuts feature billing/history/help | `.../home/presentation/global_search_surface.dart`, _fetch/_select | Các shortcut → HomePage._navigate/_openPlans | Filter các destination thật này khỏi kết quả; guard _select bổ sung | Cờ true; search aliases + native_mobile_refinement_test |
| P09 | Search plan/billing results và chip Gói/Thanh toán | cùng file, _fetch/build | Row/chip dẫn vào thông tin/màn Billing | Loại row/chip tương ứng; không thay API/search authorization; kết quả hồ sơ/kho/đi chợ/thông báo khác giữ nguyên | Cờ true; search filters test |
| P10 | Thông báo → Mở nội dung liên quan với target plan/billing/feature billing/history/help | `.../home/presentation/durable_notifications_surface.dart`, _detailBody/_related | Resolve target rồi HomePage mở Billing/Paywall | Giữ list/detail/time/read ACK; không render CTA và guard handler; CTA các target khác giữ nguyên | Cờ true; notification billing/plan/profile tests |
| P11 | HubTarget được resolve/stale handler | `.../home/presentation/home_page.dart`, _navigate/_openPlans | type billing tải payment qua initialPayment; plan và feature aliases mở helper | Guard trước fetch/payment: gọi onOpenProfile khi có, rồi return; không thay request contract | Cờ true khôi phục; search/notification + helper guards |
| P12 | Helper chung PaywallSheet.show, gồm callback cũ đã giữ | `.../home/presentation/paywall_sheet.dart`, PaywallSheet.show | push BillingPage hoặc modal PaywallSheet | Return Future<void>.value ngay, giữ trang đang mở; không chạy initialPayment/provider/load payment | Cờ true; direct constructors and shared helper test |
| P13 | Khởi tạo trực tiếp BillingPage/PaywallSheet | `lib/features/billing/billing_page.dart`, _BillingPageState; `.../home/presentation/paywall_sheet.dart`, _PaywallSheetState | init tải catalog/overview/pending hoặc summary/email và render màn | Chỉ start load trong didChangeDependencies khi policy cho phép; build trả fallback hiện hữu, không flash Billing/Paywall. Detached component không ở app scope dùng ProfilePage có sẵn | Cờ true; direct constructor no-payment-read test + existing business tests |
| P14 | Cold/warm initial URL / named Navigator request chưa đăng ký | `lib/main.dart`, HomeMindApp/MaterialApp.onGenerateRoute | Không có router named/URL riêng cho Billing; URL lạ có thể báo initial-route error | Đường chưa đăng ký dựng auth/shell hiện hữu; không đọc query để bật cờ; không route trắng/crash/redirect loop | Existing UI helper/screen hoạt động khi true; không tự tạo named Billing route mới. cold/warm tests |

## Điều hướng, fallback và cơ chế không tồn tại

App hiện dùng Navigator/MaterialPageRoute và homeSurfaceRoute. **Không tìm thấy** named Billing route, alias route đăng ký, Router/go_router, app_links/uni_links, return/next-route parser sau login, restorationScopeId/restorablePush, Android/iOS app-link intent/scheme hoặc Flutter payment callback handler. Không tạo các hệ thống đó trong nhiệm vụ này.

Destination thật là HubTarget type plan/billing và feature id billing/history/help; helper chung PaywallSheet.show là điểm push duy nhất trong lib cho BillingPage. Cả helper và constructors được chặn. HomePage redirect stale target về Cá nhân nếu shell cung cấp callback; helper đã đóng giữ caller page; direct constructors trong app scope trả auth/shell. Không push route Billing trước rồi mới pop nên không lộ màn chớp nhoáng.

`/billing`, `/plans`, `/subscription?...` và `/billing/payments/legacy` trong test là **URL không đăng ký dùng để thử denial**, không phải alias mới được hỗ trợ. MaterialApp route fallback không bypass login; session/null/loading vẫn theo cơ chế hiện hữu. Session storage/auth contract không đổi. App không có persisted navigation stack hoặc browser route-information integration; không tuyên bố đã kiểm thử browser history thật. Flutter web dùng cùng Dart navigation policy; không sửa website độc lập.

Không có mobile transaction return/callback xử lý để bỏ hoặc thay. Backend webhook, cancellation, reconciliation giữ nguyên. Không mở trình duyệt/webview quản lý gói thay thế; BillingPage chứa launchCheckout cũ chỉ tồn tại sau screen guard và purchase-off policy cũ. Legal consent URLs không thuộc Billing và không bị sửa.

## Dòng thông tin gói và layout

- Giữ nhãn **Gói của bạn**, tên từ HomeSummary.plan qua PlanInfo.of; nếu server trả tên/identifier chưa có trong catalog client, giữ nguyên chuỗi nhận thay vì gán Miễn phí.
- Khi cờ false: badge profile_upgrade và chevron không render; không có onTap, longPress, InkWell, cursor link, focus action hoặc semantics tap/longPress. Không dùng opacity/IgnorePointer/disabled placeholder để giả ẩn.
- Giữ padding, font, màu và divider; value dùng phần rộng còn lại và căn sát phải, không chừa chỗ cho chevron bị bỏ. Label có max width 50%, value co giãn và account badge dùng Flexible để wrap khi 320px/text200 thay vì overflow; không đổi handler chỉnh sửa các hàng khác.
- Thẻ VoiceQuotaPanel/BillingUsageCard vẫn lấy quota thật, không gán số/tên gói giả. Expansion Cách tính lượt ở tại chỗ được giữ.

## Khôi phục có kiểm soát

1. Review quyết định sản phẩm rồi đổi **duy nhất** PlanBillingVisibility.defaultVisible thành true trong Flutter source; không chỉnh backend flag/plan/quota để mở UI.
2. Không truyền SHOW_PLAN_AND_BILLING_UI qua Dart defines/URL: đây không phải define được hỗ trợ. Rebuild bằng các public config/flavor hiện hữu; Android allowlist và signing giữ nguyên.
3. Cập nhật test default-state và tài liệu trạng thái; giữ test denial cho scope false cùng test restored scope true. Không bỏ assertion nghiệp vụ hoặc hồi quy.
4. Chạy analyze/full tests/store restrictions và QA narrow/large text; kiểm tra từng ID P01–P14 có hành vi gốc đúng điều kiện.
5. Build/cài bản Flutter mới. Deploy API trên VPS không cập nhật app đã cài.

Checklist bật lại:

- [ ] Free/personal/family/micro_pos lấy đúng dữ liệu/tên, loading/error không tạo entitlement giả.
- [ ] Profile row, quota card, thời hạn/reset/progress/giải thích vẫn đúng.
- [ ] PlanCard và inventory/confirm/voice CTA chỉ xuất hiện theo điều kiện gốc.
- [ ] Direct constructor/helper, stale hub target, route/URL lạ xử lý đúng; không invent API/route song song.
- [ ] Thông báo giữ detail/read và resolve đúng target; email/app-link được kiểm tra qua cơ chế thực có khi bổ sung sau này.
- [ ] Callback giao dịch: hiện không tồn tại ở Flutter; nếu task sau thêm phải giữ xử lý kết quả và không bỏ webhook backend.
- [ ] Store/direct purchase restriction vẫn được kiểm chứng độc lập. Restore UI không đồng nghĩa enable PayOS/native billing.

Bật lại flag là thay đổi mới có review/test/release, không reset branch/revert mù các commit mới hơn. Rollback app UI dùng artifact Flutter trước theo quy trình phân phối tương ứng, không rollback database/API để thay một nút.

## Kiểm thử và giới hạn phát hành

SDK pin: Flutter 3.47.1. Không upgrade dependency; `pub get --enforce-lockfile`, formatter chỉ task source/tests, analyzer, full widget/unit regressions, store restrictions và debug bundle development. Test dữ liệu/service dùng fake; không gọi production/backend/email/PayOS/Gemini. Test cũ Billing/history/eligibility/paywall/plan-card/voice vẫn giữ assertions nghiệp vụ, chỉ inject restored UI rõ ràng qua `test/support/restored_plan_billing_ui.dart`; test mới default-hidden không dùng fixture đó.

`test/plan_billing_visibility_test.dart` kiểm default false, free/paid/loading/long name, no tap/parent gesture/chevron/semantics action, quota/read-only preservation, narrow320/iPhone-size393x852/text200, platform dark preference, constructors/helper, URL cold/warm, search aliases, notification read/detail/CTA, voice exhausted, confirm limit và restored UI. Font QA dùng assets thật; hệ thống chỉ có HomeMindTheme light, không bịa full dark theme support.

Local: full **631 PASS**, store policy **10 PASS**, analyze **PASS/no issues**, debug Flutter bundle development **PASS**. Ảnh before/after là Flutter widget render bằng font thật, không phải native iPhone/Android screenshot; lưu ngoài repository tại `H:\HomeMind\plan-billing-ui-20261014-01\screenshots`. Đã mở kiểm tra: hàng gói chỉ còn nhãn/tên, không khoảng trống chevron/badge; quota vẫn hiển thị. Evidence CI cuối được ghi trong báo cáo ngoài Git sau khi hoàn tất để không lấy CI SHA cũ cho commit mới. Chưa chạy physical iPhone/Android native hoặc browser history thực; không phát hành Store/TestFlight.

### Gate và ranh giới main/VPS

Dev áp dụng security/backend/flutter/dev-required-gate; publish/deploy/smoke/canary là main-only, không được tính SKIPPED thành PASS. Hosted android-e2e informational không chạy push dev; không đổi policy.

Tại baseline task: origin/dev `8fc59fc5f480c98f30e14c7fdf71f0f64c527467`, origin/main `233e71562dda9ce3f7776e2fa52f23db3d96be21`; dev ahead 11 commits/200 files, gồm auth/Family/spending/schema/migrations từ task khác. `scripts/ci/verify-promotion.py` chỉ cho same-repository **dev → main**, exact dev HEAD + green dev gate + `release_policy.require_local_native()`. Local native fingerprint được ghi cho 295 file không khớp candidate mới; không cập nhật evidence hoặc lách check chỉ để merge UI.

Nhiệm vụ này không cấp quyền phát hành/migrate toàn bộ chênh lệch đó, sửa backend/auth acceptance hoặc thay release policy. Do đó bước main/VPS **BLOCKED** cho tới khi release các dependency ngoài scope được xử lý theo nhiệm vụ riêng và acceptance chính xác đạt. Không mở/merge PR main hoặc kích hoạt deployment khi blocker còn tồn tại.

VPS runbook/`deploy/compose.yaml`/nginx hiện host API + migrator + PostgreSQL, workflow publish/deploy ba server images; không host Flutter web/mobile artifact của task. Flutter-only UI không yêu cầu restart backend; phần triển khai VPS là không áp dụng cho artifact này. Pipeline main hiện sẽ deploy cả server/migrations khi merge dev nên không trigger để tạo một “no-op” giả. Không thực hiện health/smoke production vì không có deployment được phép ở bước đang blocked; rollback server không cần thiết. App mobile cần build/cài mới, độc lập với VPS.

## File thay đổi thực tế

- Flutter source: main.dart, app/app_shell.dart, core/config/plan_billing_visibility.dart, core/l10n/app_text.dart; features/assistant/presentation/confirm_page.dart; features/billing/billing_page.dart; features/home/presentation/{profile_page,plan_card,paywall_sheet,home_page,global_search_surface,durable_notifications_surface}.dart.
- New tests: plan_billing_visibility_test.dart, support/restored_plan_billing_ui.dart. Existing test fixture caller adaptation: billing_{test,distribution_test,eligibility_test,history_test,presentation_test}.dart, payment_disabled_test.dart, paywall_sheet_test.dart, plan_card_test.dart, plan_limit_test.dart, home_hub_test.dart, native_mobile_refinement_test.dart, prototype_ui_test.dart, voice_quota_test.dart.
- Tài liệu: file này. Không backend/schema/migration/env/Android config/signing/CI workflow/Codemagic/private prompt thay đổi.

Điểm tiếp theo chính xác: commit/push các file Flutter/docs của task lên dev, chờ required checks đúng SHA cuối; giữ blocker main/VPS rõ ràng và báo kết quả ngoài commit. Không tự lấy dev CI thay cho main CI/native acceptance.
