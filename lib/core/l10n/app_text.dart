import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lớp địa phương hoá nhỏ gọn, không dùng thêm package.
///
/// Khoá tra cứu chính là câu tiếng Việt (ngôn ngữ mặc định). Khi ngôn ngữ là
/// 'vi' hoặc câu chưa có bản dịch thì trả lại đúng câu tiếng Việt gốc.
/// Dữ liệu từ server (tên sản phẩm, thông báo, câu trả lời của AI) không đi
/// qua đây. Bộ nhận giọng nói và trợ lý AI luôn dùng vi-VN.
class AppText {
  AppText._();

  static const supported = ['vi', 'en'];
  static const _storageKey = 'homemind.ui_language';

  /// Ngôn ngữ giao diện hiện tại; lắng nghe để dựng lại giao diện.
  static final ValueNotifier<String> language = ValueNotifier<String>('vi');

  static bool get isEnglish => language.value == 'en';

  /// Đổi ngôn ngữ ngay lập tức và (tuỳ chọn) nhớ lại trên máy.
  static void setLanguage(String? code, {bool persist = true}) {
    final next = supported.contains(code) ? code! : 'vi';
    language.value = next;
    if (persist) {
      _save(next);
    }
  }

  /// Đọc lựa chọn đã lưu cục bộ (dùng cho màn hình đăng nhập/giới thiệu).
  static Future<void> loadSaved() async {
    try {
      final saved = await const FlutterSecureStorage().read(key: _storageKey);
      if (saved != null && supported.contains(saved)) {
        language.value = saved;
      }
    } catch (_) {
      // Không có kho lưu trữ (ví dụ khi chạy test): giữ mặc định.
    }
  }

  static Future<void> _save(String code) async {
    try {
      await const FlutterSecureStorage().write(key: _storageKey, value: code);
    } catch (_) {
      // Bỏ qua: chỉ là tiện ích ghi nhớ.
    }
  }
}

/// Dịch một câu tiếng Việt. `{0}`, `{1}`... được thay bằng [args].
String tr(String vi, [List<Object?> args = const []]) {
  var text = AppText.isEnglish ? (_en[vi] ?? vi) : vi;
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

const Map<String, String> _en = {
  'Lượt trợ lý trong kỳ': 'Assistant usage this period',
  'Đã hết lượt trợ lý trong kỳ này.': 'No assistant uses remain this period.',
  'Đã đạt hạn mức sử dụng hiện tại.':
      'The current usage limit has been reached.',
  '⚠️ Sắp đạt giới hạn lưu trữ ({0}/{1})':
      '⚠️ Approaching the storage limit ({0}/{1})',
  'Đã đủ {0} sản phẩm. Không thể thêm sản phẩm mới.': 'The limit of {0} products has been reached. New products cannot be added.',
  'Không thể thêm sản phẩm mới vì đã đạt giới hạn lưu trữ.': 'New products cannot be added because the storage limit has been reached.',
  'Không gian hiện tại chưa có quyền mời thêm người thân.':
      'This workspace cannot invite additional relatives.',
  'Chưa thực hiện được thao tác này. Hãy thử lại.':
      'This action could not be completed. Please try again.',
  'Người thân sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành. Dữ liệu đã ghi trong nhóm được giữ nguyên.': 'This relative will lose access to the group and use the current individual allowance. Recorded group data is retained.',
  'Bạn sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành; quyền sử dụng trước khi tham gia không được khôi phục. Dữ liệu đã ghi được giữ nguyên.': 'You will lose access to the group and use the current individual allowance; earlier access is not restored. Recorded data is retained.',
  'Mọi người thân sẽ mất quyền truy cập nhóm và sử dụng hạn mức cá nhân hiện hành. Lời mời đang chờ không còn hiệu lực. Dữ liệu và quyền sử dụng của chủ nhóm được giữ nguyên.': 'All relatives will lose group access and use their current individual allowance. Pending invitations expire. The owner retains recorded data and access.',
  'Tham gia sẽ chuyển sang không gian gia đình và dùng chung hạn mức AI. Dữ liệu riêng không được nhập vào nhóm. Khi rời nhóm, bạn sử dụng hạn mức cá nhân hiện hành.': 'Joining switches to the family workspace and shared AI allowance. Personal data is not merged into the group. Leaving restores the current individual allowance.',
  'Gói Miễn phí đã đủ {0} sản phẩm. Không thể thêm sản phẩm mới.':
      'The Free plan has reached {0} products. New products cannot be added.',
  'Thông báo, {0} chưa đọc': 'Notifications, {0} unread',
  'Xóa từ khóa': 'Clear search',
  'Truy cập nhanh': 'Quick access',
  'Mời người thân': 'Invite relatives',
  'Người thân': 'Relatives',
  'AI đã dùng': 'AI usage',
  'Chu kỳ': 'Period',
  'Chưa có': 'Not available',
  'Chưa có lời mời.': 'No invitations.',
  'Chấp nhận': 'Accept',
  'Chủ nhóm': 'Owner',
  'Còn chỗ': 'Available seats',
  'Còn lại': 'Remaining',
  'Có thể mời lại sau': 'Can invite again after',
  'Dừng chia sẻ': 'Stop sharing',
  'Email tài khoản HomeMind': 'HomeMind account emails',
  'Gửi lời mời': 'Send invitations',
  'Hủy lời mời': 'Cancel invitation',
  'Không gian làm việc': 'Workspace',
  'Kiểm tra danh sách': 'Validate addresses',
  'Lượt AI trong chu kỳ': 'AI usage in this period',
  'Lần mua đã ghi': 'Recorded purchases',
  'Lời mời đã gửi': 'Sent invitations',
  'Lời mời đã nhận': 'Received invitations',
  'Rời nhóm': 'Leave group',
  'Tham gia': 'Join',
  'Thành viên': 'Member',
  'Thành viên và sử dụng': 'Members and usage',
  'Thông tin thành viên': 'Member information',
  'Từ chối': 'Decline',
  'Workspace riêng / sở hữu': 'Owned workspace',
  'Workspace được chia sẻ': 'Shared workspace',
  'Xác nhận': 'Confirm',
  'Xóa khỏi nhóm': 'Remove member',
  'Đang chờ': 'Pending',
  'Chưa rõ người ghi': 'Unknown author',
  'Chỉ xem': 'Read only',
  'Theo người ghi': 'By author',
  'lần mua': 'purchases',
  'Chưa ghi giá mua': 'Price not recorded',
  'Chưa ghi hạn sử dụng': 'Expiry not recorded',
  'Chưa ghi nơi cất': 'Location not recorded',
  'Chưa ghi số lượng': 'Quantity not recorded',
  'Giá mua: {0}': 'Purchase price: {0}',
  'Ngày nhập: {0}': 'Added on: {0}',
  'Đang tải dữ liệu': 'Loading data',
  'Đánh dấu tối đa 50 thông báo': 'Mark up to 50 notifications read',
  'Các thành viên Family dùng chung một hạn mức AI, kể cả khi chuyển về workspace riêng.': 'Family members share one AI allowance, including when switching to their private workspace.',
  'Chỉ hiển thị sử dụng trong workspace này. Không bao gồm hội thoại hay dữ liệu riêng.': 'Only usage in this workspace is shown. Private conversations and data are excluded.',
  'Nhập một hoặc nhiều email, mỗi email cách nhau bằng dấu phẩy (,). Tối đa 5 người thân trong Workspace.': 'Enter one or more emails separated by commas (,). Up to 5 relatives per workspace.',
  'Lời mời được gửi trong ứng dụng. Không gửi email. Lời mời đang chờ cũng giữ chỗ trong nhóm.': 'Invitations are delivered in the app. Email delivery is unavailable. Pending invitations reserve seats.',
  'Workspace cần quyền Family còn hiệu lực để mời người thân. Thanh toán hiện chưa được hỗ trợ.': 'An active Family entitlement is required to invite relatives. Payments are currently unavailable.',
  'Cá nhân chỉ gồm lần mua của bạn trong workspace đang chọn.': 'Personal spending includes only your purchases in the selected workspace.',
  'Số lượng chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).': 'Quantity must be between 0.001 and 999,999,999.999, with up to 3 decimal places.',
  'Số lượng của "{0}" chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).': 'Quantity for "{0}" must be between 0.001 and 999,999,999.999, with up to 3 decimal places.',
  'Xóa khỏi nhóm?': 'Remove member?',
  'Rời nhóm Family?': 'Leave the Family group?',
  'Dừng chia sẻ Family?': 'Stop Family sharing?',
  'Người thân sẽ mất quyền truy cập nhóm và trở về Free. Dữ liệu đã ghi trong nhóm được giữ nguyên.': 'This relative will lose group access and return to Free. Their recorded group data will be preserved.',
  'Bạn sẽ mất quyền truy cập nhóm và trở về gói Free, không khôi phục gói cá nhân trước khi tham gia. Dữ liệu và lịch sử thanh toán được giữ nguyên.': 'You will lose group access and return to Free. Your previous personal plan will not be restored. Data and payment history will be preserved.',
  'Mọi người thân sẽ mất quyền truy cập và trở về Free. Lời mời đang chờ không còn hiệu lực. Dữ liệu và gói hiện tại của chủ nhóm được giữ nguyên.': 'All relatives will lose access and return to Free. Pending invitations will become invalid. The owner\'s data and current plan will be preserved.',
  'Nhập từ khóa để tìm trong HomeMind': 'Enter a keyword to search HomeMind',
  'Không tìm thấy kết quả phù hợp': 'No matching results',
  'Mở chức năng': 'Open feature',
  'Còn hàng': 'In stock',
  'Đã hết hàng': 'Out of stock',
  'Cần hỗ trợ về tài khoản hoặc thanh toán?':
      'Need help with your account or billing?',
  'Tôi đã đọc và đồng ý với': 'I have read and agree to',
  'Điều khoản sử dụng': 'Terms of Service',
  'Chính sách bảo mật': 'Privacy Policy',
  'Đồng ý Điều khoản sử dụng và Chính sách bảo mật':
      'Accept the Terms of Service and Privacy Policy',
  'và': 'and',
  'Không thể mở trang pháp lý. Vui lòng thử lại.':
      'Could not open the legal page. Please try again.',
  'Vĩnh viễn': 'Lifetime',
  'Lượt dùng làm mới lúc: {0}': 'Usage resets at: {0}',
  'Cách tính lượt': 'How usage is counted',
  'Lượt dùng chung trong không gian. Kết quả trợ lý hợp lệ, kể cả câu gõ, tính một lượt. Xác nhận không tính thêm; hủy không hoàn lượt đã dùng.': 'Usage is shared in this workspace. Each valid assistant result, including typed requests, uses one turn. Confirming adds no charge; cancelling does not refund the turn.',
  'Đơn trước chưa rõ kết quả. Bấm khôi phục để kiểm tra cùng yêu cầu; không tạo đơn mới.': 'The previous order is unresolved. Recover the same request before creating another order.',
  'Khôi phục đơn đang chờ': 'Recover pending order',
  'Tải lại dữ liệu thanh toán': 'Reload billing data',
  'Đang kiểm tra...': 'Checking...',
  'Thời gian thanh toán đã kết thúc. Bấm kiểm tra trạng thái.':
      'The payment window has ended. Check the order status.',
  'Còn {0} để thanh toán': '{0} left to pay',
  'Chủ tài khoản: {0}': 'Account holder: {0}',
  'Số tài khoản: {0}': 'Account number: {0}',
  'Nội dung chuyển khoản: {0}': 'Transfer memo: {0}',
  'Số tiền: {0}': 'Amount: {0}',
  'Chưa sao chép được. Hãy thử lại.': 'Could not copy. Please try again.',
  'Đã hủy lúc: {0}': 'Cancelled at: {0}',
  'Thời điểm hủy chưa có dữ liệu': 'Cancellation time unavailable',
  'Thời điểm máy chủ xác nhận hủy':
      'Time cancellation was confirmed by the server',
  'Hỗ trợ HomeMind': 'HomeMind support',
  'Sao chép email hỗ trợ': 'Copy support email',
  'Đã sao chép email hỗ trợ': 'Support email copied',
  'Chào, {0}': 'Hello, {0}',
  'Tìm kiếm': 'Search',
  'Tìm kiếm HomeMind': 'Search HomeMind',
  'Tìm sản phẩm, món cần mua, thông báo...':
      'Find products, shopping items, notifications...',
  'Chưa tìm kiếm được. Hãy thử lại.': 'Search unavailable. Please try again.',
  'Kết quả không còn được phép mở. Hãy tải lại.':
      'This result is no longer accessible. Refresh the results.',
  'Chức năng': 'Features',
  'Thanh toán': 'Billing',
  'Chọn chức năng để mở': 'Choose a feature to open',
  'Không tìm thấy kết quả': 'No results found',
  'Trang tiếp': 'Next page',
  'Trang trước': 'Previous page',
  'Về đầu': 'First page',
  'Làm mới kết quả': 'Refresh results',
  'Chưa tải được thông báo. Hãy thử lại.':
      'Could not load notifications. Please try again.',
  'Thông báo không còn được phép mở hoặc chưa tải được.':
      'This notification is unavailable or no longer accessible.',
  'Thông báo gần đây': 'Recent notifications',
  'Tất cả thông báo': 'All notifications',
  'Chi tiết thông báo': 'Notification details',
  'Xảy ra lúc: {0}': 'Occurred at: {0}',
  'Nhận lúc: {0}': 'Received at: {0}',
  'Đang ghi nhận đã đọc...': 'Saving read status...',
  'Chưa ghi nhận đã đọc. Thử lại': 'Read status not saved. Retry',
  'Mở nội dung liên quan': 'Open related content',
  'Sản phẩm': 'Product',
  'Món cần mua': 'Shopping item',
  'Dữ liệu không còn được phép mở hoặc chưa tải được.':
      'This data is unavailable or no longer accessible.',
  'Trạng thái: {0}': 'Status: {0}',
  'Danh mục: {0}': 'Category: {0}',
  'Hạn sử dụng: {0}': 'Expiry date: {0}',
  'GÓI HIỆN TẠI': 'CURRENT PLAN',
  'Đang sử dụng': 'In use',
  'Đã dùng {0} trên {1} lượt': '{0} of {1} requests used',
  'Chi tiết gói {0}': '{0} plan details',
  '30 ngày': '30 days',
  '{0} lượt AI Voice': '{0} AI Voice requests',
  'Thời hạn 30 ngày. Không tự động gia hạn.':
      'Valid for 30 days. No automatic renewal.',
  'Chọn gói {0}': 'Choose {0}',
  'Chưa thể sử dụng': 'Not available yet',
  'Sắp ra mắt': 'Coming soon',
  'Đang phát triển': 'In development',
  'Mã QR thanh toán': 'Payment QR code',
  'Quét bằng ứng dụng ngân hàng': 'Scan with your banking app',
  'Chuyển đúng số tiền và nội dung hiển thị bên dưới.':
      'Use the exact amount and transfer description below.',
  'Thông tin chuyển khoản': 'Transfer details',
  'Đã sao chép số tài khoản': 'Account number copied',
  'Đã sao chép nội dung chuyển khoản': 'Transfer description copied',
  'Đang xác minh': 'Under review',
  'Đã thanh toán': 'Paid',
  'Đã hủy': 'Cancelled',
  'Chờ thanh toán': 'Awaiting payment',
  'Mã đơn: {0}': 'Order: {0}',
  'Chưa có giao dịch': 'No transactions yet',
  'Các giao dịch mua gói của bạn sẽ xuất hiện tại đây.':
      'Your plan purchases will appear here.',
  'Chọn gói phù hợp': 'Find your plan',
  'HomeMind đang hoàn thiện': 'Coming to HomeMind',
  'Gói năm': 'Annual plan',
  'Hiện tại bạn có thể sử dụng gói 30 ngày.':
      'You can use a 30-day plan today.',
  'Gia hạn tự động': 'Automatic renewal',
  'HomeMind đang hoàn thiện tính năng này':
      'HomeMind is working on this feature',
  'Thanh toán của bạn': 'Your payment',
  'Yêu cầu hoàn tiền': 'Refund request',
  'Tính năng gửi yêu cầu hoàn tiền đang được HomeMind hoàn thiện.':
      'HomeMind is working on refund requests.',
  "Lượt trợ lý của gói đang dùng": "Assistant usage for the current plan",
  'Kỳ hiện tại kết thúc: {0}': 'Current period ends: {0}',
  'Ngân hàng (BIN): {0}': 'Bank (BIN): {0}',
  'Đơn chưa thanh toán hết hạn: {0}': 'Unpaid order expires: {0}',
  'Sao chép số tài khoản': 'Copy account number',
  'Sao chép nội dung chuyển khoản': 'Copy transfer description',
  "Chưa tải được hạn mức trợ lý. Hãy thử lại.":
      "Unable to load assistant quota. Try again.",
  "Còn {0} lượt trong kỳ": "{0} requests remaining this period",
  "Lượt dùng chung trong workspace. Kết quả trợ lý hợp lệ, gồm câu gõ, tính một lượt; xác nhận hoặc hủy không tính thêm.": "Shared workspace quota. A valid assistant result, including typed input, uses one request; confirmation and cancellation use no extra requests.",
  "Gói đang dùng đã hết lượt trợ lý trong kỳ này.":
      "The current plan has no assistant requests remaining this period.",
  "Đã hết lượt. Có thể nâng lên gói phù hợp cao hơn.":
      "No requests left. You can upgrade to an eligible higher plan.",
  "Đã hết lượt. Hãy chờ kỳ tiếp theo; gia hạn đang cập nhật.":
      "No requests left. Wait for the next period; renewal is coming soon.",
  "{0}: {1} VND / 30 ngày. Nâng gói thu đủ giá, áp dụng ngay sau xác minh thanh toán và bắt đầu kỳ mới với lượt dùng bằng 0. Không cộng thời gian hoặc lượt cũ. Không tự động gia hạn.": "{0}: {1} VND / 30 days. Upgrades charge the full price, apply immediately after payment verification and start a new period with zero usage. Previous time and requests do not carry over. No automatic renewal.",
  "{0} · {1} VND / 30 ngày": "{0} · {1} VND / 30 days",
  "Đã thay bằng gói mới. Hạn ban đầu: {0}":
      "Superseded by a new plan. Original expiry: {0}",
  "Gia hạn — Đang cập nhật": "Renewal — Coming soon",
  "Gói năm — Đang cập nhật": "Annual plan — Coming soon",
  "Chưa khả dụng": "Unavailable",
  "Yêu cầu hoàn tiền — Đang cập nhật": "Refund request — Coming soon",
  "Chức năng chưa hoạt động; chưa gửi yêu cầu hoặc email. Hỗ trợ: homemind.support@gmail.com": "This feature is unavailable; no request or email has been sent. Support: homemind.support@gmail.com",
  "29.000đ / 30 ngày": "29,000 VND / 30 days",
  "59.000đ / 30 ngày": "59,000 VND / 30 days",
  "149.000đ / 30 ngày": "149,000 VND / 30 days",
  'Số điện thoại liên hệ': 'Contact phone number',
  'Sửa số điện thoại liên hệ': 'Edit contact phone number',
  'Nhập số điện thoại liên hệ': 'Enter contact phone number',
  'Số điện thoại đăng nhập': 'Login phone number',
  'Số điện thoại đăng nhập (không bắt buộc)': 'Login phone number (optional)',
  'Thay đổi chưa được lưu. Hồ sơ đã đối soát với máy chủ.': 'The change was not saved. Your profile has been checked against the server.',
  'Chưa xác nhận được trạng thái lưu. Hãy tải lại hồ sơ trước khi thử lại.': 'The save outcome is unconfirmed. Reload your profile before trying again.',
  'Thông tin chưa hợp lệ. Kiểm tra trường đang sửa.':
      'Invalid information. Check the field you are editing.',
  'Cho tiệm tạp hóa': 'For grocery stores',
  'Đã nhập hàng': 'Restocked',
  'Xác nhận đã mua': 'Confirm purchase',
  'Xác nhận đã nhập': 'Confirm restock',
  'Số lượng đã mua': 'Quantity bought',
  'Số lượng đã nhập': 'Quantity restocked',
  'Hãy nhập số lượng (lớn hơn 0).': 'Enter the quantity (more than 0).',
  'Nhập số lượng thực tế đã mua. HomeMind tự cập nhật vào tủ đồ cho bạn.': 'Enter the quantity you actually bought. HomeMind updates your pantry automatically.',
  'Nhập số lượng thực tế đã nhập. HomeMind tự cập nhật vào kho cho bạn.': 'Enter the quantity you actually received. HomeMind updates your stock automatically.',
  'Đã nhập hàng {0} {1} "{2}".': 'Restocked {0} {1} of "{2}".',
  'Đã mua {0} {1} "{2}".': 'Bought {0} {1} of "{2}".',
  'Chưa ghi được "{0}". Bạn thử lại nhé.':
      'Could not save "{0}". Please try again.',
  'Nhập vào kho': 'Add to stock',
  'Cất vào tủ đồ': 'Put in pantry',
  'Cất vào {0}': 'Put in {0}',
  'Lưu vào {0}': 'Save to {0}',
  'Nhập số lượng thực tế đã về để cập nhật vào {0}.':
      'Enter the quantity that actually arrived to update your {0}.',
  'Hạn sử dụng (nếu có)': 'Expiry date (optional)',
  'Hãy nhập số lượng thực nhận (lớn hơn 0).':
      'Enter the quantity received (more than 0).',
  'Hãy nhập đơn vị, ví dụ: gói, kg, chai.':
      'Enter a unit, for example: pack, kg, bottle.',
  'Đã nhập {0} {1} "{2}" vào kho.': 'Added {0} {1} of "{2}" to stock.',
  'Đã cất {0} {1} "{2}" vào tủ đồ.': 'Put {0} {1} of "{2}" in your pantry.',
  'Chưa cất được "{0}" vào kho. Bạn thử lại nhé.':
      'Could not store "{0}". Please try again.',
  'Bạn có muốn thêm món này vào {0} không?':
      'Do you want to add this item to your {0}?',
  'Không, chỉ báo hết': 'No, just mark it as out',
  'kho': 'stock',
  'tủ đồ': 'pantry',
  'danh sách cần nhập': 'restock list',
  'danh sách đi chợ': 'shopping list',
  'Thêm {0} vào {1}{2}': 'Add {0} to {1}{2}',
  '{0} và thêm vào {1}': '{0} and add to {1}',
  'Thêm vào {0}': 'Add to {0}',
  'Thêm vào {0}: {1}': 'Add to {0}: {1}',
  'Hiện còn {0}': 'Currently {0} left',
  'Hết toàn bộ': 'All gone',
  'Chỉ trừ một phần': 'Only part of it',
  'Số lượng đã trừ': 'Quantity used',
  'Hãy nhập số lượng đã trừ (lớn hơn 0).':
      'Enter the quantity used (more than 0).',
  'Trong kho chỉ còn {0}, không thể trừ nhiều hơn.':
      'Only {0} left in stock, you cannot use more than that.',
  'Chi tiết': 'Details',
  // ── Thông báo ──
  'Chưa đọc': 'Unread',
  'Đã đọc': 'Read',
  'Đánh dấu đã đọc': 'Mark as read',
  'Đánh dấu đã đọc hết': 'Mark all as read',
  'Chưa lưu được. Bạn thử lại nhé.': 'Could not save. Please try again.',
  'Chạm vào thông báo hoặc bấm "Đã đọc" để chuyển xuống mục Đã đọc.':
      'Tap a notification or press "✓ Read" to move it to Read.',
  // ── Nhóm sản phẩm ──
  'Đồ tươi': 'Fresh food',
  'Đồ khô & lương thực': 'Dry goods & staples',
  'Gia vị': 'Spices',
  'Đồ uống': 'Drinks',
  'Đồ dùng gia đình': 'Household items',
  'Mỹ phẩm & làm đẹp': 'Beauty & cosmetics',
  'Sữa rửa mặt, toner, kem dưỡng, son, nước hoa':
      'Face wash, toner, moisturizer, lipstick, perfume',
  'Khác': 'Other',
  'Rau, củ, thịt, cá, trứng, sữa': 'Vegetables, meat, fish, eggs, milk',
  'Gạo, mì, bún, bánh kẹo, cá khô, đồ hộp':
      'Rice, noodles, snacks, dried fish, canned food',
  'Nước mắm, dầu ăn, đường, muối, tương':
      'Fish sauce, oil, sugar, salt, sauces',
  'Nước ngọt, nước suối, bia, trà, cà phê':
      'Soft drinks, water, beer, tea, coffee',
  'Bột giặt, giấy vệ sinh, dầu gội, kem đánh răng, pin':
      'Detergent, toilet paper, shampoo, toothpaste, batteries',
  'Những món chưa xếp được vào nhóm nào': 'Items that fit no other group',
  // ── Điều hướng dưới ──
  'Trang chủ': 'Home',
  'Tủ đồ': 'Fridge & pantry',
  'Kho hàng': 'Stock',
  'Đi chợ': 'Shopping',
  'Cần nhập': 'To restock',
  'Cá nhân': 'Profile',
  'Nói': 'Speak',

  // ── App shell ──
  'Đang phân tích câu lệnh với AI...': 'Analyzing your command with AI...',
  'Danh sách cần mua 🛒': 'Shopping list 🛒',
  'Mở Danh sách Mua sắm': 'Open shopping list',
  'Sản phẩm sắp hết hạn ⚠️': 'Items expiring soon ⚠️',
  'Tồn kho trong tủ 📦': 'Items in your fridge & pantry 📦',
  'Xem Tủ đồ': 'View fridge & pantry',
  'Bạn nói nhanh quá, đợi một chút rồi thử lại nhé.':
      'You are speaking too fast. Please wait a moment and try again.',
  'Trợ lý đang bận. Bạn thử lại sau ít giây nhé.':
      'The assistant is busy. Please try again in a few seconds.',
  'Phiên đăng nhập đã hết hạn. Bạn đăng nhập lại nhé.':
      'Your session has expired. Please sign in again.',
  'Không kết nối được mạng. Bạn kiểm tra Wi-Fi rồi thử lại nhé.':
      'No network connection. Check your Wi-Fi and try again.',
  'Chưa xử lý được câu này. Bạn thử nói lại nhé.':
      'Could not process that. Please try saying it again.',
  'Trợ lý giọng nói HomeMind': 'HomeMind voice assistant',
  'Câu hỏi của bạn:': 'Your question:',
  'HomeMind trả lời:': 'HomeMind says:',
  'Đóng': 'Close',

  // ── Hồ sơ ──
  'Hồ sơ & Tài khoản': 'Profile & Account',
  'Đăng xuất tài khoản': 'Sign out',
  'Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng HomeMind không?':
      'Are you sure you want to sign out of HomeMind?',
  'Hủy': 'Cancel',
  'Huỷ': 'Cancel',
  'Đăng xuất': 'Sign out',
  'Người dùng HomeMind': 'HomeMind user',
  'Chưa cập nhật': 'Not set',
  'Không gian HomeMind': 'HomeMind workspace',
  'Tài khoản gia đình': 'Family account',
  'Tài khoản cửa hàng': 'Store account',
  'Thành viên gia đình': 'Family member',
  'Chủ cửa hàng': 'Store owner',
  'Đang đăng nhập': 'Signed in',
  'Cửa hàng tạp hóa': 'Grocery store',
  'Tủ đồ gia đình & mua sắm thông minh': 'Family pantry & smart shopping',
  'Mặt hàng quầy kệ': 'Shelf items',
  'Món trong tủ': 'Items in stock',
  'Cửa hàng': 'Store',
  'Gia đình': 'Family',
  'Không gian': 'Workspace',
  'Cần chú ý': 'Needs attention',
  'Thông tin chi tiết': 'Details',
  'Tên': 'Name',
  'Số điện thoại': 'Phone number',
  'Địa chỉ': 'Address',
  'Ngôn ngữ': 'Language',
  'Lưu': 'Save',
  'Đã lưu': 'Saved',
  'Sửa tên hiển thị': 'Edit display name',
  'Sửa số điện thoại': 'Edit phone number',
  'Sửa địa chỉ': 'Edit address',
  'Chọn ngôn ngữ': 'Choose language',
  'Tên hiển thị': 'Display name',
  'Nhập số điện thoại': 'Enter your phone number',
  'Nhập địa chỉ': 'Enter your address',
  'Bạn chưa nhập tên.': 'Please enter your name.',
  'Tên tối đa 120 ký tự.': 'Name can be at most 120 characters.',
  'Số điện thoại cần 8-20 ký tự gồm số, khoảng trắng, +, - hoặc .':
      'Phone number needs 8-20 characters: digits, spaces, +, - or .',
  'Địa chỉ tối đa 300 ký tự.': 'Address can be at most 300 characters.',
  'Chưa lưu được. Bạn kiểm tra mạng rồi thử lại nhé.':
      'Could not save. Check your connection and try again.',
  'Trợ lý giọng nói vẫn nghe tiếng Việt':
      'The voice assistant still listens in Vietnamese',

  // ── Trang chủ ──
  'Chưa tải được dữ liệu.\nBạn kiểm tra mạng rồi thử lại nhé.':
      'Could not load data.\nCheck your connection and try again.',
  'Thử lại': 'Try again',
  'Tìm hàng hoá, sản phẩm...': 'Search goods, products...',
  'Tìm đồ dùng, thực phẩm...': 'Search household items, food...',
  'Mọi lời yêu cầu của bạn, chúng tôi đều lắng nghe':
      'We listen to every request you make',
  'Hàng sắp hết hạn ⚠️': 'Items expiring soon ⚠️',
  'Sắp hết hạn': 'Expiring soon',
  'Nên bán hoặc dùng trước những món này': 'Sell or use these items first',
  'Ưu tiên dùng trước để tránh lãng phí': 'Use these first to avoid waste',
  'Xem tất cả': 'View all',
  'Không có món nào sắp hết hạn.': 'Nothing is expiring soon.',
  'Rất gấp': 'Very urgent',
  'Sắp tới hạn': 'Due soon',
  'Quá hạn {0} ngày': 'Expired {0} days ago',
  'Hết hạn hôm nay': 'Expires today',
  'Còn 1 ngày': '1 day left',
  'Còn {0} ngày': '{0} days left',
  'Xem chi tiết': 'View details',
  'Hàng cần nhập thêm': 'Items to restock',
  'Danh sách cần mua': 'Shopping list',
  'Những món cần nhập thêm': 'Items that need restocking',
  'Các món đã hết hoặc được thêm để mua lại':
      'Items that ran out or were added to buy again',
  'Chưa có mặt hàng nào cần nhập.': 'No items to restock yet.',
  'Chưa có món nào cần mua.': 'Nothing to buy yet.',
  'Trạng thái': 'Status',
  'Hết tồn kho': 'Out of stock',
  'Đã báo hết hàng': 'Reported as out',
  'Cần mua': 'To buy',
  'Xem danh sách': 'View list',
  'Quầy kệ tiệm tạp hóa': 'Store shelves',
  'Tủ đồ của bạn': 'Your fridge & pantry',
  'Hàng hóa đang bày bán tại quầy kệ tiệm': 'Goods on display in your store',
  'Những món đang còn trong nhà': 'Items you still have at home',
  'Chỉ hiển thị món đang còn và đang dùng trong nhà':
      'Only items still in stock at home',
  'Chưa có mặt hàng trên quầy kệ.': 'No items on the shelves yet.',
  'Chưa có món nào trong tủ.': 'Nothing in your fridge & pantry yet.',
  'Tạp hóa': 'Grocery',
  'Còn': 'In stock',
  'Quầy kệ': 'Shelves',
  'Sắp hết': 'Running low',
  'Quá hạn': 'Overdue',
  'Hết hạn': 'Expired',
  'Gói Quản lý Tiệm Tạp Hóa': 'Grocery Store Plan',
  'Gói Free hiện tại': 'Current Free plan',
  'Đang quản lý {0}/{1} mặt hàng quầy kệ': 'Managing {0}/{1} shelf items',
  'Đã dùng {0}/{1} sản phẩm miễn phí': 'Used {0}/{1} free products',

  // ── Tủ đồ ──
  'Tất cả': 'All',
  'Đã hết hạn': 'Expired',
  'An toàn': 'Safe',
  'Đã báo hết "{0}" và thêm vào danh sách cần nhập.':
      'Reported "{0}" as out and added it to the restock list.',
  'Đã báo hết "{0}" và thêm vào danh sách cần mua.':
      'Reported "{0}" as out and added it to the shopping list.',
  'Đã báo hết "{0}".': 'Reported "{0}" as out.',
  'Chưa báo hết được "{0}". Bạn thử lại nhé.':
      'Could not report "{0}" as out. Please try again.',
  'Chưa tải được danh sách.\nBạn kiểm tra mạng rồi thử lại nhé.':
      'Could not load the list.\nCheck your connection and try again.',
  'Kho hàng của tiệm': 'Store stock',
  'Những món đang có trong tiệm.': 'Items currently in your store.',
  'Những món đang có trong nhà.': 'Items currently at home.',
  '{0} món đang có · Món sắp hết hạn xếp trước':
      '{0} items in stock · Expiring items first',
  'Tìm mặt hàng trên quầy kệ tiệm...': 'Search items on store shelves...',
  'Tìm sản phẩm trong tủ nhà...': 'Search items in your pantry...',
  '⚠️ Chỉ hiện hàng sắp hết hạn': '⚠️ Only show items expiring soon',
  '⚠️ Chỉ hiện sản phẩm sắp quá hạn': '⚠️ Only show items expiring soon',
  'Đang lọc các món sắp quá hạn': 'Filtering items expiring soon',
  'Hiện tất cả': 'Show all',
  'Không tìm thấy sản phẩm phù hợp.': 'No matching items found.',
  'Đặt lại bộ lọc': 'Reset filters',
  'Còn {0} {1}': '{0} {1} left',
  'Báo hết hàng': 'Report out of stock',
  'Đánh dấu Hết': 'Mark as out',
  'HSD: {0}': 'Exp: {0}',

  // ── Đi chợ ──
  'Đã ghi nhập "{0}".': 'Recorded "{0}" as restocked.',
  'Đã ghi mua "{0}".': 'Recorded "{0}" as bought.',
  'Đã bỏ qua "{0}".': 'Skipped "{0}".',
  'Đã đưa "{0}" về danh sách cần nhập.':
      'Moved "{0}" back to the restock list.',
  'Đã đưa "{0}" về danh sách cần mua.':
      'Moved "{0}" back to the shopping list.',
  'Chưa cập nhật được "{0}". Bạn thử lại nhé.':
      'Could not update "{0}". Please try again.',
  'Đã thêm "{0}" vào danh sách cần nhập.': 'Added "{0}" to the restock list.',
  'Đã thêm "{0}" vào danh sách cần mua.': 'Added "{0}" to the shopping list.',
  'Chưa thêm được "{0}". Bạn thử lại nhé.':
      'Could not add "{0}". Please try again.',
  'Tìm món cần nhập...': 'Search items to restock...',
  'Tìm kiếm sản phẩm cần mua...': 'Search items to buy...',
  'Hàng cần nhập thêm ': 'Items to restock ',
  'Danh sách cần mua ': 'Shopping list ',
  'Những món tiệm cần nhập thêm': 'Items your store needs to restock',
  'Những món bạn cần mua lại hoặc bổ sung cho gia đình':
      'Items to buy again or top up for your family',
  'Cần nhập ({0})': 'To restock ({0})',
  'Cần mua ({0})': 'To buy ({0})',
  'Hết hàng ({0})': 'Out of stock ({0})',
  'Đã hết ({0})': 'Ran out ({0})',
  'Đã nhập ({0})': 'Restocked ({0})',
  'Đã mua ({0})': 'Bought ({0})',
  'Đã bỏ qua ({0})': 'Skipped ({0})',
  'Không có mặt hàng nào cần nhập.': 'No items to restock.',
  'Không có món nào cần mua.': 'Nothing to buy.',
  'Tự thêm vì đã hết': 'Added automatically (ran out)',
  'Đã nhập': 'Restocked',
  'Đã mua': 'Bought',
  'Bỏ qua': 'Skip',
  'Không có mặt hàng nào hết trên quầy kệ.': 'No shelf items are out of stock.',
  'Không có món nào đã hết.': 'Nothing has run out.',
  'Đã trong danh sách': 'Already on the list',
  'Cần nhập lại': 'Restock again',
  'Cần mua lại': 'Buy again',
  'Chưa có mặt hàng nào đã nhập về tiệm.': 'Nothing restocked yet.',
  'Chưa có món nào đã mua.': 'Nothing bought yet.',
  'Nhập tiếp': 'Restock',
  'Mua lại': 'Buy again',
  'Chưa có món nào bị bỏ qua.': 'Nothing skipped yet.',
  'Khôi phục': 'Restore',
  'Gợi ý: hàng đã hết trên kệ': 'Suggestions: items out on the shelves',
  'Gợi ý mua sắm thông minh': 'Smart shopping suggestions',
  'Thêm': 'Add',
  'Bạn đã dùng hết {0}': 'You have run out of {0}',
  'Bạn có muốn thêm món này vào danh sách cần mua không?':
      'Do you want to add this item to your shopping list?',
  'Không': 'No',
  'Thêm vào mua sắm': 'Add to shopping list',

  // ── Đăng nhập / giới thiệu ──
  'Không kết nối được mạng. Kiểm tra Wi-Fi rồi thử lại.':
      'No network connection. Check your Wi-Fi and try again.',
  'Quay lại': 'Back',
  'Đăng nhập': 'Sign in',
  'Chào mừng bạn đến với HomeMind': 'Welcome to HomeMind',
  'Nhập email của bạn': 'Enter your email',
  'Bạn chưa nhập email': 'Please enter your email',
  'Mật khẩu': 'Password',
  'Nhập mật khẩu': 'Enter your password',
  'Hiện mật khẩu': 'Show password',
  'Ẩn mật khẩu': 'Hide password',
  'Bạn chưa nhập mật khẩu': 'Please enter your password',
  'Dùng tài khoản thử': 'Use a demo account',
  'Nói để thêm đồ': 'Speak to add items',
  'Bấm nút micro rồi nói, ví dụ "Tôi vừa mua 2 hộp sữa". HomeMind sẽ tự ghi vào tủ đồ giúp bạn.': 'Tap the mic and speak, e.g. "I just bought 2 cartons of milk". HomeMind adds it to your pantry for you.',
  'Xem đồ sắp hết hạn': 'See what is expiring',
  'HomeMind nhắc bạn món nào sắp hết hạn để dùng trước, không bị bỏ phí.': 'HomeMind reminds you which items expire soon so you use them first and avoid waste.',
  'Danh sách đi chợ': 'Shopping list',
  'Món nào hết, bạn thêm vào danh sách đi chợ. Ra chợ chỉ cần mở ra xem là biết mua gì.': 'Add what runs out to your shopping list. At the market, just open it to see what to buy.',
  'Bắt đầu': 'Get started',
  'Tiếp theo': 'Next',

  // ── Voice sheet ──
  'Đang nghe...': 'Listening...',
  'Sẵn sàng': 'Ready',
  'Không thể dùng microphone': 'Microphone unavailable',
  'Không thể khởi tạo microphone: {0}': 'Could not start the microphone: {0}',
  'Nói hoặc chọn câu gợi ý bên dưới...': 'Speak or pick a suggestion below...',

  // ── Màn xác nhận ──
  'HomeMind đã xử lý câu lệnh của bạn.': 'HomeMind processed your command.',
  'món mới': 'new item',
  ', hạn {0}': ', expires {0}',
  'Thêm {0} vào tủ đồ{1}': 'Add {0} to your pantry{1}',
  'món này': 'this item',
  'Đánh dấu hết {0}': 'Mark {0} as out',
  'Trừ {0} {1}': 'Use {0} {1}',
  '{0} và thêm vào danh sách đi chợ': '{0} and add to your shopping list',
  'Thêm vào danh sách đi chợ': 'Add to your shopping list',
  'Thêm vào danh sách đi chợ: {0}': 'Add to your shopping list: {0}',
  'Bạn chưa nhập tên món.': 'Please enter the item name.',
  'Hãy nhập số lượng lớn hơn 0.': 'Enter a quantity greater than 0.',
  'Hãy nhập đơn vị, ví dụ: hộp, kg, chai.':
      'Enter a unit, e.g. box, kg, bottle.',
  'Số lượng chưa đúng. Hãy nhập số lớn hơn 0.':
      'Invalid quantity. Enter a number greater than 0.',
  'Có món chưa có tên. Hãy nhập tên món.':
      'An item has no name. Please enter it.',
  'Số lượng của "{0}" chưa đúng.': 'The quantity for "{0}" is invalid.',
  'Hãy nhập số lượng của "{0}" (lớn hơn 0).':
      'Enter a quantity greater than 0 for "{0}".',
  'Hãy nhập đơn vị của "{0}", ví dụ: hộp, kg, chai.':
      'Enter a unit for "{0}", e.g. box, kg, bottle.',
  'Bỏ món này': 'Remove this item',
  'Thêm món cần mua…': 'Add an item to buy…',
  'Thêm món cần nhập…': 'Add an item to restock…',
  'Bấm nút Nói rồi đọc "cần nhập 5 thùng bia" để thêm nhanh.':
      'Tap Speak and say "need 5 crates of beer" to add quickly.',
  'Bấm nút Nói rồi đọc "nhớ mua nửa ký sả" để thêm nhanh.': 'Tap Speak and say "remember to buy half a kilo of lemongrass" to add quickly.',
  'Gõ tên món vào ô phía trên, hoặc bấm nút Nói rồi đọc "nhớ mua sả".':
      'Type an item above, or tap Speak and say "remember to buy lemongrass".',
  'Bỏ qua khỏi {0}: {1}': 'Skip from {0}: {1}',
  'Chưa có món nào để bỏ qua.': 'There is nothing left to skip.',
  'Chưa lưu được. Bạn bấm Thử lại nhé.': 'Could not save. Tap Try again.',
  'Chọn hạn sử dụng': 'Choose expiry date',
  'Chọn': 'Select',
  'Tên món': 'Item name',
  'Số lượng': 'Quantity',
  'Đơn vị': 'Unit',
  'hộp, kg…': 'box, kg…',
  'Hạn sử dụng': 'Expiry date',
  'Chưa chọn - bấm để chọn ngày': 'Not set - tap to pick a date',
  'Xoá hạn sử dụng': 'Clear expiry date',
  'Để trống nếu hết hẳn': 'Leave empty if fully out',
  'Món {0}': 'Item {0}',
  'Kiểm tra lại trước khi lưu': 'Review before saving',
  'Kết quả': 'Result',
  'Bạn đã nói: “{0}”': 'You said: “{0}”',
  'Chạm vào ô để sửa nếu chưa đúng': 'Tap a field to edit if it is wrong',
  'Đã hiểu': 'Got it',

  // ── Thông báo ──
  'Thông báo': 'Notifications',
  'Đọc tất cả': 'Mark all as read',
  'Chưa đọc ({0})': 'Unread ({0})',
  'Không có thông báo nào.': 'No notifications.',

  // ── Gói dịch vụ / nâng cấp ──
  'Miễn phí': 'Free',
  '0đ': '0₫',
  '29.000đ/tháng': '29,000₫/month',
  '59.000đ/tháng': '59,000₫/month',
  '149.000đ/tháng': '149,000₫/month',
  'mặt hàng': 'products',
  'món': 'items',
  'sản phẩm': 'products',
  'Gói {0} · {1}/{2} mặt hàng': '{0} plan · {1}/{2} products',
  'Gói {0} · {1} {2} — không giới hạn': '{0} plan · {1} {2} — unlimited',
  'Nâng lên Gia đình': 'Upgrade to Family',
  'Gói Miễn phí · {0}/{1} {2}': 'Free plan · {0}/{1} {2}',
  'Còn {0} chỗ trống. Nâng cấp Micro-POS (149.000đ / 30 ngày) để quản lý kho và được nhắc nhập hàng.': '{0} spots left. Upgrade to Micro-POS (149,000₫ / 30 days) to manage stock and get restock reminders.',
  'Còn {0} chỗ trống. Nâng cấp để lưu không giới hạn và dùng trợ lý AI thông minh hơn.': '{0} spots left. Upgrade to save without limits and get a smarter AI assistant.',
  'Sắp đầy! Chỉ còn {0} chỗ trống': 'Almost full! Only {0} spots left',
  'Đã đầy {0}/{0} mặt hàng. Nâng cấp để tiếp tục thêm hàng.':
      'Full: {0}/{0} products. Upgrade to keep adding products.',
  'Đã đầy {0}/{0} sản phẩm. Nâng cấp để tiếp tục thêm sản phẩm.':
      'Full: {0}/{0} products. Upgrade to keep adding products.',
  'Nâng cấp từ 149.000đ / 30 ngày': 'Upgrade from 149,000₫ / 30 days',
  'Nâng cấp từ 29.000đ / 30 ngày': 'Upgrade from 29,000₫ / 30 days',
  'Xem các gói': 'See plans',
  'Trung bình mỗi hộ gia đình lãng phí khoảng 123.000đ/tháng vì đồ hết hạn':
      'On average, a household wastes about 123,000₫/month on expired food',
  'Đã ghi nhận yêu cầu nâng cấp gói {0}. Chúng tôi sẽ liên hệ bạn sớm.': 'Your upgrade request for the {0} plan is recorded. We will contact you soon.',
  'Đổi gói': 'Change plan',
  'tài khoản của bạn': 'your account',
  'Đã ghi nhận! Chúng tôi sẽ liên hệ bạn qua {0} để hoàn tất.':
      'Recorded! We will contact you via {0} to finish.',
  'Chưa gửi được yêu cầu. Bạn kiểm tra mạng rồi thử lại nhé.':
      'Could not send your request. Check your connection and try again.',
  'Chọn gói phù hợp với bạn': 'Choose the plan that fits you',
  'Đăng ký gói {0}': 'Subscribe to {0}',
  'Thanh toán sắp ra mắt — hiện chúng tôi hỗ trợ đăng ký trực tiếp.':
      'Payments are coming soon — for now we handle sign-ups directly.',
  'Không giới hạn sản phẩm': 'Unlimited products',
  'AI nâng cao': 'Advanced AI',
  'Tối đa 5 thành viên': 'Up to 5 members',
  'Chia sẻ real-time': 'Real-time sharing',
  'Quản lý kho': 'Stock management',
  'Nhắc nhập hàng': 'Restock reminders',
  '{0} mặt hàng': '{0} products',
  '{0} sản phẩm': '{0} products',
  'AI cơ bản': 'Basic AI',
  '{0} lượt trợ lý AI / 30 ngày': '{0} AI assistant uses / 30 days',
  'Tối đa {0} sản phẩm': 'Up to {0} products',
  'Gói hiện tại': 'Current plan',
  'Phổ biến': 'Popular',
  '⚠️ Gói miễn phí sắp đầy ({0}/{1})': '⚠️ Free plan almost full ({0}/{1})',
  'Nâng cấp': 'Upgrade',
  'Xem gói hiện tại': 'View current plan',
  'Thanh toán gói hiện chưa được hỗ trợ trong phiên bản này. Bạn vẫn có thể xem gói hiện tại và lịch sử thanh toán.': 'Plan payments are currently unavailable in this version. You can still view your current plan and payment history.',
  'Còn {0} chỗ trống trong gói hiện tại.':
      '{0} spots left in your current plan.',
  'Gói miễn phí đã đủ {0} sản phẩm. Bạn vẫn lưu được lần này; hãy nâng cấp để tiếp tục thêm sản phẩm.': 'Free plan is full at {0} products. You can still save this time; upgrade to keep adding products.',
  'Gói của bạn': 'Your plan',
  'Gói của bạn đã đủ số lượng sản phẩm. Hãy nâng cấp để thêm sản phẩm mới.':
      'Your plan has reached its product limit. Upgrade to add new products.',
  'Gói Miễn phí đã đủ {0} sản phẩm. Nâng cấp để thêm sản phẩm mới.':
      'The Free plan is full at {0} products. Upgrade to add new products.',
  'Nâng cấp để thêm': 'Upgrade to add',
  'Gói {0} đã đủ {1} mặt hàng. Hãy liên hệ để nâng hạn mức.':
      'The {0} plan is full at {1} products. Contact us to raise the limit.',
  'Đã đủ hạn mức': 'Limit reached',
  'Đã đầy {0}/{0} sản phẩm — không thể thêm sản phẩm mới':
      'Full: {0}/{0} products — cannot add new products',
  'Đã đầy {0}/{0} mặt hàng — không thể thêm mặt hàng mới':
      'Full: {0}/{0} products — cannot add new products',

  // Billing: prices, verification and coverage remain server-authoritative.
  'Đang tải': 'Loading',
  'Chưa tải được thanh toán. Kiểm tra mạng và thử lại.':
      'Could not load billing. Check your connection and try again.',
  'Chưa hoàn tất yêu cầu. Kiểm tra trạng thái trước khi tạo đơn khác.': 'The request did not complete. Check its status before creating another order.',
  'Xác nhận gói': 'Confirm plan',
  'Tạo đơn thanh toán': 'Create payment order',
  'Không mở thanh toán ngoài trong bản phân phối này.':
      'External checkout is unavailable in this distribution.',
  'Chưa mở được trình duyệt.': 'Could not open the browser.',
  'Đã xác minh thanh toán và cấp gói': 'Payment verified and plan activated',
  'Đã ghi nhận tiền — chờ kiểm tra trước khi cấp gói':
      'Payment received — awaiting review before plan activation',
  'Chưa đủ tiền — chưa cấp gói': 'Underpaid — plan not activated',
  'Đã hủy đơn chưa thanh toán': 'Unpaid order cancelled',
  'Đơn đã hết hạn': 'Order expired',
  'Đơn cần được kiểm tra — chưa cấp gói':
      'Order needs review — plan not activated',
  'Đang chờ xác minh — chưa cấp gói':
      'Awaiting verification — plan not activated',
  'Gói & thanh toán': 'Plans & billing',
  'Gói được cấp thủ công vẫn được giữ nguyên. Cần liên hệ chủ sản phẩm để xét chuyển đổi.': 'Your manually assigned plan is preserved. Contact the product owner to review a change.',
  'Bản phân phối qua cửa hàng chưa bật thanh toán ngoài. Bạn vẫn xem được gói và lịch sử.': 'External checkout is disabled in store distributions. You can still view your plan and history.',
  'Thanh toán chưa được cấu hình trên máy chủ.':
      'Billing is not configured on the server.',
  'Thanh toán đã được máy chủ xác minh. Gói và thời gian áp dụng hiển thị bên trên.': 'The server has verified payment. Your plan and coverage dates are shown above.',
  'Mở lại trang thanh toán': 'Reopen checkout',
  'Kiểm tra trạng thái': 'Check status',
  'Hủy đơn chưa thanh toán': 'Cancel unpaid order',
  'Không giới hạn số sản phẩm; các chức năng hiện có.':
      'Unlimited products; existing features.',
  'Gia hạn': 'Renew',
  'Lịch sử thanh toán': 'Payment history',
  'Xem thêm': 'Load more',
  'Tải lại': 'Reload',
  '{0}: {1} VND / 1 tháng lịch. Không tự động gia hạn. Gia hạn hoặc đổi gói sẽ áp dụng sau toàn bộ thời gian đã trả tiền. Đơn có số tiền hoặc trạng thái bất thường sẽ chờ kiểm tra.': '{0}: {1} VND / 1 calendar month. No automatic renewal. Renewal or plan changes start after all paid coverage. Unusual amounts or statuses require review.',
  'Gói hiện tại: {0}': 'Current plan: {0}',
  'Hiệu lực: {0} → {1}': 'Coverage: {0} → {1}',
  'Đã mua, chờ áp dụng: {0} từ {1} đến {2}':
      'Purchased, scheduled: {0} from {1} to {2}',
  'Mã đơn: {0} · Đã nhận: {1} VND': 'Order: {0} · Received: {1} VND',
  'Số tiền đơn: {0} VND': 'Order amount: {0} VND',
  'Tạo lúc: {0}': 'Created at: {0}',
  'Đã thanh toán lúc: {0}': 'Paid at: {0}',
  '{0} · {1} VND / tháng': '{0} · {1} VND / month',
  'Tối đa {0} sản phẩm; các chức năng hiện có.':
      'Up to {0} products; existing features.',
  'Tối đa 500 sản phẩm': 'Up to 500 products',
  'Còn {0} chỗ trống. Nâng cấp gói Cá nhân hoặc Gia đình để lưu không giới hạn sản phẩm.': '{0} spots left. Upgrade to Personal or Family to save unlimited products.',
  'Gói Cá nhân': 'Personal',
  'Hồ sơ': 'Profile',
  'Gói': 'Plans',
  'Đọc lần đầu: {0}': 'First read: {0}',
  'Có thông báo mới. Tải lại để xem.': 'New notifications. Reload to view.',
  'Có thông báo mới. Quay lại để tải lại danh sách.':
      'New notifications. Go back to reload the list.',
  'Chào mừng đến HomeMind': 'Welcome to HomeMind',
  'Tài khoản của bạn đã sẵn sàng.': 'Your account is ready.',
  'Bạn có thể quản lý đồ dùng, danh sách mua và hồ sơ trong HomeMind.':
      'Manage your inventory, shopping list and profile in HomeMind.',
  'Hồ sơ đã cập nhật': 'Profile updated',
  'Thay đổi hồ sơ của bạn đã được lưu.':
      'Your profile changes have been saved.',
  'Mở Hồ sơ để xem thông tin hiện tại.':
      'Open Profile to view your current information.',
  'Bảo mật tài khoản đã cập nhật': 'Account security updated',
  'Một thay đổi bảo mật đã được xác nhận.':
      'An account security change was confirmed.',
  'Mở Bảo mật tài khoản để xem thông tin hiện tại.':
      'Open Account security to view current information.',
  'Đăng nhập thành công': 'Signed in successfully',
  'Một phiên đăng nhập mới đã được mở.': 'A new sign-in session was opened.',
  'Nếu không phải bạn, hãy kiểm tra Bảo mật tài khoản.':
      'If this was not you, check Account security.',
  'Đã đăng xuất': 'Signed out',
  'Yêu cầu đăng xuất của bạn đã được xác nhận.':
      'Your sign-out request was confirmed.',
  'Phiên đã đăng xuất không còn được dùng để truy cập tài khoản.':
      'The signed-out session can no longer access your account.',
  'Đã nhận hàng': 'Items received',
  'Đã thêm món cần mua': 'Shopping item added',
  'Danh sách mua đã cập nhật': 'Shopping list updated',
  'Đã thêm vào kho': 'Added to inventory',
  'Sản phẩm đã cập nhật': 'Product updated',
  'Đã cập nhật tồn kho': 'Stock updated',
  'Đã xác nhận thao tác trợ lý': 'Assistant operation confirmed',
  'Thao tác của bạn đã được lưu.': 'Your operation has been saved.',
  'Mở dữ liệu liên quan để xem kết quả hiện tại.':
      'Open the related data to view the current result.',
  'Đã tạo đơn thanh toán': 'Payment order created',
  'Thanh toán đã xác minh và gói đã kích hoạt':
      'Payment verified and plan activated',
  'Thanh toán đang chờ kiểm tra': 'Payment awaiting review',
  'Đơn thanh toán đã hủy': 'Payment order cancelled',
  'Đơn thanh toán đã hết hạn': 'Payment order expired',
  'Mở thanh toán để xem trạng thái đã được máy chủ xác nhận.':
      'Open Billing to view the server-confirmed status.',
  'Thông báo này không thay thế trạng thái gói và lịch sử thanh toán.':
      'This notification does not replace plan status or payment history.',
  'Kỳ lượt trợ lý mới đã bắt đầu': 'A new assistant usage period has started',
  'Đã dùng hết lượt trợ lý trong kỳ':
      'Assistant allowance exhausted for this period',
  'Mở Hồ sơ để xem lượt dùng và thời gian làm mới.':
      'Open Profile to view usage and its reset time.',
  'Lượt trợ lý dùng chung trong không gian. Gói Miễn phí không hết hạn.': 'Assistant usage is shared within the workspace. Free access does not expire.',
  'Gói trả phí đã kết thúc': 'Paid plan ended',
  'Không gian đã trở về gói Miễn phí.': 'Your workspace has returned to Free.',
  'Dữ liệu và lịch sử được giữ nguyên. Gói Miễn phí có quyền truy cập vĩnh viễn.':
      'Data and history are preserved. Free access is lifetime.',
  'Mở sản phẩm để xem tồn kho hiện tại.':
      'Open the product to view current stock.',
  'Bạn vẫn xem được gói và lịch sử.': 'You can view your plan and history.',
  'Tủ lạnh': 'Fridge',
  'Ngăn đá': 'Freezer',
  'Tủ bếp': 'Kitchen cabinet',
  'Kệ khô': 'Dry shelf',
  'Phòng tắm': 'Bathroom',
  'Kho sau': 'Back storeroom',
  'Tủ mát': 'Chiller',
  'Tủ đông': 'Freezer cabinet',
  'Khác…': 'Other…',
  '≈ {0} mỗi đơn vị': '≈ {0} per unit',
  '≈ {0} / {1}': '≈ {0} / {1}',
  'Giá mua & nơi cất': 'Price & storage place',
  'Không bắt buộc': 'Optional',
  'Tổng tiền đã mua': 'Total amount paid',
  'VD: 45000, 45k, 1,2tr': 'e.g. 45000, 45k, 1.2m',
  'Chưa đọc được số tiền': 'Couldn\'t read the amount',
  'Nơi cất': 'Storage place',
  'VD: Tủ gỗ phòng khách': 'e.g. Living room wooden cabinet',
  'Chưa đọc được số tiền. Bạn nhập lại hoặc để trống nhé.':
      'Couldn\'t read the amount. Re-enter it or leave it empty.',
  'Chưa đọc được số tiền của "{0}". Bạn nhập lại hoặc để trống nhé.':
      'Couldn\'t read the amount for "{0}". Re-enter it or leave it empty.',
  'Nơi cất: {0}': 'Stored in: {0}',
  'Nhập giá cho "{0}"': 'Enter price for "{0}"',
  'Lần mua ngày {0}': 'Purchased on {0}',
  'Để sau': 'Later',
  'Lưu giá': 'Save price',
  'Tháng {0}/{1}': '{0}/{1}',
  'Gần như không đổi so với tháng trước': 'About the same as last month',
  'Tăng {0}% so với tháng trước': 'Up {0}% from last month',
  'Giảm {0}% so với tháng trước': 'Down {0}% from last month',
  'Chưa lưu được giá. Bạn thử lại nhé.':
      'Couldn\'t save the price. Please try again.',
  'Chi phí nhập hàng': 'Stock purchase cost',
  'Chi tiêu': 'Spending',
  'Chưa tải được chi tiêu. Bạn thử lại nhé.':
      'Couldn\'t load spending. Please try again.',
  '{0} lần mua chưa có giá nên chưa được cộng vào tổng. Nhập giá để số liệu chính xác hơn.': '{0} purchases have no price yet, so they are not in the total. Add prices for a more accurate figure.',
  'Chưa có lần mua nào trong tháng này. Khi bạn lưu đồ vào kho, hãy nhập giá để theo dõi chi tiêu.': 'No purchases this month yet. When you save items to your stock, add prices to track spending.',
  'Theo nhóm': 'By category',
  'Chưa có giá ({0})': 'No price yet ({0})',
  'Đang hiển thị {0} lần mua gần nhất. Nhập giá xong sẽ hiện thêm.':
      'Showing the latest {0} purchases. More appear as you add prices.',
  'Tháng trước': 'Previous month',
  'Tháng sau': 'Next month',
  'Đã nhập hàng trong tháng': 'Stock bought this month',
  'Đã chi trong tháng': 'Spent this month',
  'Tổng chi {0}': 'Total spent {0}',
  'Chưa phân loại': 'Uncategorized',
  'Đã có giá: {0}/{1} lần mua': 'Priced: {0}/{1} purchases',
  'Mua ngày {0}': 'Bought on {0}',
  'Nhập giá': 'Add price',
  'Nhập hàng tháng {0}': 'Stock bought in month {0}',
  'Chi tiêu tháng {0}': 'Spending in month {0}',
  '{0} lần mua chưa có giá': '{0} purchases without price',
  '{0} lần mua chưa có giá, tổng thực tế có thể cao hơn':
      '{0} purchases without price; the real total may be higher',
  'Chi tiêu 💰': 'Spending 💰',
  'Xem chi tiêu': 'View spending',
  'Số lượng chưa đúng (phải lớn hơn 0).':
      'The quantity is not valid (must be greater than 0).',
  'Số lượng của "{0}" chưa đúng (phải lớn hơn 0).':
      'The quantity for "{0}" is not valid (must be greater than 0).',
  'Số lượng đã nhập (tuỳ chọn)': 'Quantity received (optional)',
  'Số lượng đã mua (tuỳ chọn)': 'Quantity bought (optional)',
  'Đơn vị (tuỳ chọn)': 'Unit (optional)',
  'Số lượng (tuỳ chọn)': 'Quantity (optional)',
  'Đã nhập hàng "{0}".': 'Received "{0}".',
  'Đã nhập hàng {0} "{1}".': 'Received {0} "{1}".',
  'Đã mua "{0}".': 'Bought "{0}".',
  'Đã mua {0} "{1}".': 'Bought {0} "{1}".',
  'Đặt hạn sử dụng cho {0}': 'Set expiry date for {0}',
  'Đặt hạn {0} cho {1}': 'Set expiry {0} for {1}',
  'Hãy chọn hạn sử dụng.': 'Please choose an expiry date.',
  'Trong kho chỉ còn {0}, ít hơn số bạn nhập.':
      'Only {0} in stock, fewer than you entered.',
  'Số lượng có hạn này': 'Quantity with this expiry',
  'Bỏ trống = tất cả': 'Leave empty = all',
  'Việc {0}/{1} trong câu bạn vừa nói': 'Task {0}/{1} from what you said',
};
