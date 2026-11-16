# شبح — Shabah

مكتبة `dylib` لنظام iOS تُحقن داخل تطبيق وتتحكم في الموقع الذي يراه التطبيق.
تشمل: تثبيت موقع، والسير على مسار، والمفضلة، وواجهة عربية وإنجليزية.

## المكونات

| الملف | الوظيفة |
|---|---|
| `Source/SHInit.m` | نقطة التشغيل عند تحميل المكتبة |
| `Source/SHLocationHooks.m` | اعتراض `CLLocationManager` و`MKUserLocation`، وإرسال الموقع المزيّف كل ثانية |
| `Source/SHPersistence.m` | حفظ الحالة والإعدادات والمفضلة |
| `Source/SHRouteSimulator.m` | محاكاة السير على مسار بسرعة المشي أو الدراجة أو السيارة |
| `Source/SHOverlay.m` | الزر العائم (يمكن سحبه). النقر المزدوج بثلاثة أصابع يخفيه أو يظهره |
| `Source/SHMapPickerViewController.m` | شاشة الخريطة: بحث، إحداثيات، تثبيت، مسار، حفظ |
| `Source/SHBookmarksViewController.m` | قائمة المواقع المحفوظة |
| `Source/SHLocalization.m` | نصوص الواجهة بالعربية والإنجليزية |

## البناء

### GitHub Actions (لا تحتاج Mac)
كل `push` يبني المكتبة تلقائيًا.
بعد انتهاء البناء نزّل الملف من تبويب **Actions**، ثم افتح آخر تشغيل، ثم **Artifacts**، ثم `Shabah-dylib`.

### Mac أو WSL مع Theos
```bash
export THEOS=~/theos
make FINALPACKAGE=1
```

## الحقن في تطبيق
استخدم أداة توقيع تدعم حقن الـ dylib، مثل Sideloadly أو ESign أو Feather.
ضع `Shabah.dylib` في مجلد `Frameworks` داخل التطبيق، ثم أعد التوقيع.
