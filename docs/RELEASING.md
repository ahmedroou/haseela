# نشر تحديث لحصيلة

المستودع العام: https://github.com/ahmedroou/haseela

1. غيّري version في pubspec.yaml من 1.0.1+2 إلى رقم أعلى، مثل 1.0.2+3. لا تعيدي استخدام رقم البناء ولا المفتاح.
2. شغّلي flutter analyze ثم flutter test --reporter expanded.
3. شغّلي flutter build apk --release --split-per-abi بالمفتاح الأصلي الخارجي. لا ترفعيه ولا كلمات مروره إلى GitHub.
4. انسخي APKs من build/app/outputs/flutter-apk إلى artifacts/releases بالأسماء haseela-VERSION-arm64-v8a.apk وhaseela-VERSION-armeabi-v7a.apk وhaseela-VERSION-x86_64.apk، مع استبدال VERSION.
5. تحققي من توقيع كل ملف بواسطة apksigner verify --verbose --print-certs، ومن أرقام الحزمة والإصدار بواسطة aapt dump badging.
6. احفظي تغييرات المصدر وادفعيها إلى GitHub. ضعي ملاحظات الإصدار للمستخدمة في ملف نصي UTF-8.
7. أنشئي وسم vVERSION على commit المصدر الذي أنتج APKs، وارفعي الوسم. أنشئي GitHub Release بالملفات الثلاثة. يجب أن يكون إصدارًا مستقرًا منشورًا ومحددًا كـLatest.

مثال باستخدام GitHub CLI، بعد حفظ المصدر وإنشاء الوسم ورفعه:

```powershell
gh release create v1.0.2 artifacts/releases/haseela-1.0.2-arm64-v8a.apk artifacts/releases/haseela-1.0.2-armeabi-v7a.apk artifacts/releases/haseela-1.0.2-x86_64.apk --repo ahmedroou/haseela --verify-tag --latest --title 'حصيلة 1.0.2' --notes-file docs/release-notes-1.0.2.md
gh api repos/ahmedroou/haseela/releases/latest --jq '{tag: .tag_name, assets: [.assets[] | {name, size, digest}]}'
```

تحققي أن assets تضم المعماريات الثلاث، ولكل منها digest يبدأ بـsha256:. يعتمد التطبيق على هذه البصمة ويرفض ملفًا بلا بصمة أو ببيانات غير سليمة. لا تنشري الملفات باسم ثابت app-release.apk؛ اسم كل ملف يتضمن رقم النسخة ومعماريتها.

اختبري الترقية على هاتف يحتفظ بحسابات وطلبات: ظهور التنبيه، تنزيل التحديث، رفض/منح إذن تثبيت التطبيقات، إلغاء/إكمال المثبّت، ثم التأكد من بقاء البيانات. لم يُختبر مثبّت Android فعليًا على جهاز أثناء إنشاء الإصدار 1.0.1؛ يجب إبقاء هذا الحد واضحًا.

النسخة الشاملة اختيارية للتحميل اليدوي؛ التحديث الداخلي يختار دائمًا ملف المعمارية المناسب. لا يمكن تثبيت نسخة شاملة ذات versionCode أقل فوق نسخة معمارية، لذا استخدمي المعمارية نفسها عند التحديث اليدوي من نسخة معمارية. يحافظ Flutter على تسلسل versionCode لكل معمارية عند رفع رقم البناء.
