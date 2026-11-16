#import "SHPrefix.h"
#import "SHPersistence.h"

NSString *SHText(NSString *key) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // key: @[ English, Arabic ]
        table = @{
            @"title":         @[@"Shabah",                     @"شبح"],
            @"search":        @[@"Search a place or lat, lon",     @"ابحث عن مكان أو أدخل الإحداثيات"],
            @"hint":          @[@"Long-press the map to pick a point", @"اضغط مطولًا على الخريطة لاختيار نقطة"],
            @"status_on":     @[@"Spoofing active",                @"تزييف الموقع مفعّل"],
            @"status_off":    @[@"Real location",                  @"الموقع الحقيقي"],
            @"fluct":         @[@"Natural jitter",                 @"تذبذب طبيعي"],
            @"walk":          @[@"Walk",                           @"مشي"],
            @"bike":          @[@"Bike",                           @"دراجة"],
            @"car":           @[@"Car",                            @"سيارة"],
            @"apply":         @[@"Set location",                   @"تثبيت الموقع"],
            @"route":         @[@"Go along route",                 @"السير بمسار"],
            @"save":          @[@"Save",                           @"حفظ"],
            @"bookmarks":     @[@"Bookmarks",                      @"المفضلة"],
            @"stop":          @[@"Stop spoofing",                  @"إيقاف التزييف"],
            @"close":         @[@"Close",                          @"إغلاق"],
            @"cancel":        @[@"Cancel",                         @"إلغاء"],
            @"ok":            @[@"OK",                             @"حسنًا"],
            @"need_pin":      @[@"Pick a point on the map first.", @"اختر نقطة على الخريطة أولًا."],
            @"need_start":    @[@"Set a starting location first, then pick the destination.", @"ثبّت موقع البداية أولًا ثم اختر الوجهة."],
            @"route_fail":    @[@"Could not find a route.",        @"تعذّر إيجاد مسار."],
            @"search_fail":   @[@"No results found.",              @"لا توجد نتائج."],
            @"bookmark_name": @[@"Bookmark name",                  @"اسم الموقع"],
            @"no_bookmarks":  @[@"No saved places yet.",           @"لا توجد مواقع محفوظة."],
            @"route_done":    @[@"Route finished",                 @"انتهى المسار"],
            @"lang":          @[@"ع",                              @"EN"],
        };
    });
    NSArray<NSString *> *pair = table[key];
    if (!pair) return key;
    return [SHPersistence shared].arabic ? pair[1] : pair[0];
}
