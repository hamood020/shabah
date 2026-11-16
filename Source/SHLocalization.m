#import "SHPrefix.h"
#import "SHPersistence.h"

NSString *SHText(NSString *key) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // key: @[ English, Arabic ]
        table = @{
            @"app_name":        @[@"Shabah", @"شبح"],
            @"search":          @[@"Search or paste a Google Maps link", @"ابحث أو الصق رابط خرائط Google"],
            @"hint":            @[@"Long-press the map to pick a point", @"اضغط مطولًا على الخريطة لاختيار نقطة"],

            @"status_on":       @[@"Spoofing active", @"تزييف الموقع مفعّل"],
            @"status_off":      @[@"Real location", @"الموقع الحقيقي"],
            @"status_route":    @[@"Moving along route", @"يسير على المسار"],
            @"status_paused":   @[@"Route paused", @"المسار متوقف مؤقتًا"],
            @"status_joystick": @[@"Joystick control", @"التحكم بالعصا"],
            @"status_glide":    @[@"Moving to new location", @"ينتقل للموقع الجديد"],

            @"chip_set":        @[@"Set", @"تثبيت"],
            @"chip_stop":       @[@"Stop", @"إيقاف"],
            @"chip_resume":     @[@"Resume", @"استئناف"],

            @"tab_location":    @[@"Location", @"الموقع"],
            @"tab_route":       @[@"Route", @"المسار"],
            @"tab_joystick":    @[@"Joystick", @"التحكم"],
            @"tab_places":      @[@"Places", @"المفضلة"],

            @"lat":             @[@"Latitude", @"خط العرض"],
            @"lon":             @[@"Longitude", @"خط الطول"],
            @"jitter":          @[@"Natural jitter", @"تذبذب طبيعي"],
            @"radius":          @[@"Jitter radius", @"نصف قطر التذبذب"],
            @"meters_fmt":      @[@"%d m", @"%d م"],
            @"altitude":        @[@"Altitude (m)", @"الارتفاع (م)"],
            @"auto_stop":       @[@"Auto stop", @"إيقاف تلقائي"],
            @"never":           @[@"Never", @"أبدًا"],
            @"min30":           @[@"After 30 minutes", @"بعد 30 دقيقة"],
            @"hour1":           @[@"After 1 hour", @"بعد ساعة"],
            @"hour2":           @[@"After 2 hours", @"بعد ساعتين"],
            @"hours_fmt":       @[@"After %d hours", @"بعد %d ساعات"],
            @"glide":           @[@"Gradual transition", @"انتقال تدريجي"],
            @"apply":           @[@"Set location", @"تثبيت الموقع"],
            @"stop":            @[@"Stop spoofing", @"إيقاف التزييف"],

            @"route_hint":      @[@"Long-press the map to add stops. The route starts from your current spoofed location.", @"اضغط مطولًا على الخريطة لإضافة نقاط. يبدأ المسار من موقعك المزيّف الحالي."],
            @"stops_fmt":       @[@"Stops: %lu", @"النقاط: %lu"],
            @"undo":            @[@"Undo", @"تراجع"],
            @"clear":           @[@"Clear", @"مسح"],
            @"walk":            @[@"Walk", @"مشي"],
            @"bike":            @[@"Bike", @"دراجة"],
            @"car":             @[@"Car", @"سيارة"],
            @"speed":           @[@"Speed", @"السرعة"],
            @"kmh_fmt":         @[@"%d km/h", @"%d كم/س"],
            @"loop":            @[@"Loop back and forth", @"تكرار ذهابًا وإيابًا"],
            @"realistic":       @[@"Realistic motion (turns and stops)", @"حركة واقعية (منعطفات وتوقفات)"],
            @"route_start":     @[@"Start route", @"ابدأ المسار"],
            @"route_pause":     @[@"Pause", @"إيقاف مؤقت"],
            @"route_resume":    @[@"Resume", @"استئناف"],
            @"route_building":  @[@"Calculating…", @"جاري حساب المسار…"],
            @"route_left_fmt":  @[@"%.1f km left · %d min", @"متبقي %.1f كم · %d د"],
            @"route_done":      @[@"Route finished", @"انتهى المسار"],
            @"route_fail":      @[@"Couldn't build a route.", @"تعذّر بناء المسار."],
            @"need_stops":      @[@"Add at least one stop on the map.", @"أضف نقطة واحدة على الأقل على الخريطة."],

            @"joy_show":        @[@"Show joystick over the app", @"إظهار العصا فوق التطبيق"],
            @"joy_note":        @[@"The joystick stays on screen after you close the map. Tap the lock to keep moving in one direction.", @"تبقى العصا على الشاشة بعد إغلاق الخريطة. اضغط القفل لتستمر بالحركة في نفس الاتجاه."],
            @"joy_need":        @[@"Set a location first, then use the joystick.", @"ثبّت موقعًا أولًا ثم استخدم العصا."],

            @"bookmarks":       @[@"Bookmarks", @"المفضلة"],
            @"recents":         @[@"Recent", @"الأخيرة"],
            @"no_bookmarks":    @[@"Save places with the star button", @"احفظ المواقع بزر النجمة"],
            @"no_recents":      @[@"Places you set appear here", @"تظهر هنا المواقع التي تثبّتها"],
            @"export":          @[@"Export", @"تصدير"],
            @"import":          @[@"Import", @"استيراد"],
            @"edit":            @[@"Edit", @"تعديل"],
            @"done":            @[@"Done", @"تم"],
            @"exported":        @[@"Bookmarks copied to the clipboard.", @"تم نسخ المفضلة إلى الحافظة."],
            @"imported_fmt":    @[@"Imported %ld places.", @"تم استيراد %ld موقع."],
            @"import_fail":     @[@"The clipboard doesn't contain exported places.", @"الحافظة لا تحتوي مواقع مُصدّرة."],
            @"rename":          @[@"Rename", @"إعادة تسمية"],
            @"delete":          @[@"Delete", @"حذف"],
            @"save":            @[@"Save", @"حفظ"],
            @"cancel":          @[@"Cancel", @"إلغاء"],
            @"ok":              @[@"OK", @"حسنًا"],
            @"bookmark_name":   @[@"Place name", @"اسم الموقع"],
            @"saved":           @[@"Saved", @"تم الحفظ"],

            @"need_pin":        @[@"Pick a point on the map first.", @"اختر نقطة على الخريطة أولًا."],
            @"search_fail":     @[@"No results found.", @"لا توجد نتائج."],

            @"settings":        @[@"Settings", @"الإعدادات"],
            @"general":         @[@"General", @"عام"],
            @"language":        @[@"Language", @"اللغة"],
            @"map_style":       @[@"Map style", @"نمط الخريطة"],
            @"style_standard":  @[@"Standard", @"عادي"],
            @"style_satellite": @[@"Satellite", @"قمر صناعي"],
            @"style_hybrid":    @[@"Hybrid", @"هجين"],
            @"style_night":     @[@"Night", @"ليلي"],
            @"check_updates":   @[@"Check for updates", @"التحقق من التحديثات"],
            @"check_now":       @[@"Check now", @"تحقق الآن"],
            @"version":         @[@"Version", @"الإصدار"],
            @"copy_log":        @[@"Copy diagnostics log", @"نسخ سجل التشخيص"],
            @"log_copied":      @[@"Log copied.", @"تم نسخ السجل."],
            @"project_page":    @[@"Project page", @"صفحة المشروع"],
            @"about":           @[@"About", @"حول"],
            @"help":            @[@"How to use", @"طريقة الاستخدام"],
            @"help_tap":        @[@"Tap the ghost button to open the map", @"اضغط زر الشبح لفتح الخريطة"],
            @"help_hold":       @[@"Long-press it for quick actions", @"اضغط مطولًا عليه للقائمة السريعة"],
            @"help_three":      @[@"Double-tap with three fingers to hide it", @"نقر مزدوج بثلاثة أصابع لإخفائه"],
            @"update_fmt":      @[@"Version %@ is available.", @"الإصدار %@ متوفر."],
            @"up_to_date":      @[@"You have the latest version.", @"لديك أحدث إصدار."],
            @"update_fail":     @[@"Couldn't check for updates.", @"تعذّر التحقق من التحديثات."],
            @"open":            @[@"Open", @"فتح"],
            @"open_map":        @[@"Open map", @"فتح الخريطة"],
            @"joystick":        @[@"Joystick", @"عصا التحكم"],
            @"close":           @[@"Close", @"إغلاق"],
        };
    });
    NSArray<NSString *> *pair = table[key];
    if (!pair) return key;
    return [SHPersistence shared].arabic ? pair[1] : pair[0];
}
