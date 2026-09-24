import 'package:flutter/material.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.onFinish, super.key});

  final VoidCallback onFinish;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<({IconData icon, String title, String subtitle})> get _slides => [
    (
      icon: Icons.mic_rounded,
      title: tr('Nói để thêm đồ'),
      subtitle: tr(
        'Bấm nút micro rồi nói, ví dụ "Tôi vừa mua 2 hộp sữa". HomeMind sẽ tự ghi vào tủ đồ giúp bạn.',
      ),
    ),
    (
      icon: Icons.event_available_rounded,
      title: tr('Xem đồ sắp hết hạn'),
      subtitle: tr(
        'HomeMind nhắc bạn món nào sắp hết hạn để dùng trước, không bị bỏ phí.',
      ),
    ),
    (
      icon: Icons.shopping_cart_rounded,
      title: tr('Danh sách đi chợ'),
      subtitle: tr(
        'Món nào hết, bạn thêm vào danh sách đi chợ. Ra chợ chỉ cần mở ra xem là biết mua gì.',
      ),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _slides.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/logos/logo_256.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'HomeMind',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: widget.onFinish,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    child: Text(
                      tr('Bỏ qua'),
                      style: TextStyle(
                        color: HomeMindTheme.textSub,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final item = _slides[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        Container(
                          width: 160,
                          height: 160,
                          decoration: const BoxDecoration(
                            color: HomeMindTheme.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.icon,
                            size: 84,
                            color: HomeMindTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: HomeMindTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          item.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            color: HomeMindTheme.textSub,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 28 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isActive
                              ? HomeMindTheme.primary
                              : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HomeMindTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            HomeMindTheme.radiusMd,
                          ),
                        ),
                      ),
                      child: Text(
                        isLast ? tr('Bắt đầu') : tr('Tiếp theo'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
