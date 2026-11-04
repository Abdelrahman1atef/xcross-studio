// Feature 024: the stock symbols, from the Material icon set that ships with
// Flutter under its open licence.
import 'package:flutter/material.dart';

/// `Filled`, `Outline` or `Round`, as the symbol set draws it.
enum ClipartStyle { filled, outline, round }

/// One symbol in its three styles.
class Clipart {
  const Clipart(this.name, this.filled, this.outline, this.round);

  final String name;
  final IconData filled;
  final IconData outline;
  final IconData round;

  IconData of(ClipartStyle style) => switch (style) {
    ClipartStyle.filled => filled,
    ClipartStyle.outline => outline,
    ClipartStyle.round => round,
  };
}

/// Symbols whose name has [query], in a stable order.
List<Clipart> searchClipart(String query) {
  final text = query.trim().toLowerCase().replaceAll(' ', '_');
  if (text.isEmpty) return clipartSet;
  return [
    for (final item in clipartSet)
      if (item.name.contains(text)) item,
  ];
}

const clipartSet = <Clipart>[
  Clipart(
    'agriculture',
    Icons.agriculture,
    Icons.agriculture_outlined,
    Icons.agriculture_rounded,
  ),
  Clipart(
    'apartment',
    Icons.apartment,
    Icons.apartment_outlined,
    Icons.apartment_rounded,
  ),
  Clipart(
    'article',
    Icons.article,
    Icons.article_outlined,
    Icons.article_rounded,
  ),
  Clipart(
    'attach_money',
    Icons.attach_money,
    Icons.attach_money_outlined,
    Icons.attach_money_rounded,
  ),
  Clipart(
    'bank',
    Icons.account_balance,
    Icons.account_balance_outlined,
    Icons.account_balance_rounded,
  ),
  Clipart(
    'beach',
    Icons.beach_access,
    Icons.beach_access_outlined,
    Icons.beach_access_rounded,
  ),
  Clipart(
    'bike',
    Icons.directions_bike,
    Icons.directions_bike_outlined,
    Icons.directions_bike_rounded,
  ),
  Clipart(
    'bluetooth',
    Icons.bluetooth,
    Icons.bluetooth_outlined,
    Icons.bluetooth_rounded,
  ),
  Clipart('bolt', Icons.bolt, Icons.bolt_outlined, Icons.bolt_rounded),
  Clipart('book', Icons.book, Icons.book_outlined, Icons.book_rounded),
  Clipart('brush', Icons.brush, Icons.brush_outlined, Icons.brush_rounded),
  Clipart('build', Icons.build, Icons.build_outlined, Icons.build_rounded),
  Clipart(
    'cafe',
    Icons.local_cafe,
    Icons.local_cafe_outlined,
    Icons.local_cafe_rounded,
  ),
  Clipart('cake', Icons.cake, Icons.cake_outlined, Icons.cake_rounded),
  Clipart(
    'calendar',
    Icons.calendar_today,
    Icons.calendar_today_outlined,
    Icons.calendar_today_rounded,
  ),
  Clipart(
    'camera',
    Icons.camera_alt,
    Icons.camera_alt_outlined,
    Icons.camera_alt_rounded,
  ),
  Clipart(
    'car',
    Icons.directions_car,
    Icons.directions_car_outlined,
    Icons.directions_car_rounded,
  ),
  Clipart(
    'cart',
    Icons.shopping_cart,
    Icons.shopping_cart_outlined,
    Icons.shopping_cart_rounded,
  ),
  Clipart('chat', Icons.chat, Icons.chat_outlined, Icons.chat_rounded),
  Clipart(
    'check',
    Icons.check_circle,
    Icons.check_circle_outlined,
    Icons.check_circle_rounded,
  ),
  Clipart(
    'child',
    Icons.child_care,
    Icons.child_care_outlined,
    Icons.child_care_rounded,
  ),
  Clipart(
    'clock',
    Icons.schedule,
    Icons.schedule_outlined,
    Icons.schedule_rounded,
  ),
  Clipart('cloud', Icons.cloud, Icons.cloud_outlined, Icons.cloud_rounded),
  Clipart('code', Icons.code, Icons.code_outlined, Icons.code_rounded),
  Clipart(
    'compass',
    Icons.explore,
    Icons.explore_outlined,
    Icons.explore_rounded,
  ),
  Clipart(
    'credit_card',
    Icons.credit_card,
    Icons.credit_card_outlined,
    Icons.credit_card_rounded,
  ),
  Clipart(
    'delivery',
    Icons.delivery_dining,
    Icons.delivery_dining_outlined,
    Icons.delivery_dining_rounded,
  ),
  Clipart(
    'diamond',
    Icons.diamond,
    Icons.diamond_outlined,
    Icons.diamond_rounded,
  ),
  Clipart(
    'doctor',
    Icons.medical_services,
    Icons.medical_services_outlined,
    Icons.medical_services_rounded,
  ),
  Clipart(
    'document',
    Icons.description,
    Icons.description_outlined,
    Icons.description_rounded,
  ),
  Clipart(
    'download',
    Icons.download,
    Icons.download_outlined,
    Icons.download_rounded,
  ),
  Clipart('edit', Icons.edit, Icons.edit_outlined, Icons.edit_rounded),
  Clipart('email', Icons.email, Icons.email_outlined, Icons.email_rounded),
  Clipart(
    'emoji',
    Icons.emoji_emotions,
    Icons.emoji_emotions_outlined,
    Icons.emoji_emotions_rounded,
  ),
  Clipart('event', Icons.event, Icons.event_outlined, Icons.event_rounded),
  Clipart(
    'ev_station',
    Icons.ev_station,
    Icons.ev_station_outlined,
    Icons.ev_station_rounded,
  ),
  Clipart(
    'favorite',
    Icons.favorite,
    Icons.favorite_outlined,
    Icons.favorite_rounded,
  ),
  Clipart(
    'fire',
    Icons.local_fire_department,
    Icons.local_fire_department_outlined,
    Icons.local_fire_department_rounded,
  ),
  Clipart(
    'fitness',
    Icons.fitness_center,
    Icons.fitness_center_outlined,
    Icons.fitness_center_rounded,
  ),
  Clipart('flight', Icons.flight, Icons.flight_outlined, Icons.flight_rounded),
  Clipart('folder', Icons.folder, Icons.folder_outlined, Icons.folder_rounded),
  Clipart('forest', Icons.forest, Icons.forest_outlined, Icons.forest_rounded),
  Clipart(
    'fuel',
    Icons.local_gas_station,
    Icons.local_gas_station_outlined,
    Icons.local_gas_station_rounded,
  ),
  Clipart(
    'game',
    Icons.sports_esports,
    Icons.sports_esports_outlined,
    Icons.sports_esports_rounded,
  ),
  Clipart('groups', Icons.groups, Icons.groups_outlined, Icons.groups_rounded),
  Clipart(
    'handshake',
    Icons.handshake,
    Icons.handshake_outlined,
    Icons.handshake_rounded,
  ),
  Clipart(
    'headphones',
    Icons.headphones,
    Icons.headphones_outlined,
    Icons.headphones_rounded,
  ),
  Clipart(
    'healing',
    Icons.healing,
    Icons.healing_outlined,
    Icons.healing_rounded,
  ),
  Clipart(
    'heart_monitor',
    Icons.monitor_heart,
    Icons.monitor_heart_outlined,
    Icons.monitor_heart_rounded,
  ),
  Clipart('home', Icons.home, Icons.home_outlined, Icons.home_rounded),
  Clipart(
    'hospital',
    Icons.local_hospital,
    Icons.local_hospital_outlined,
    Icons.local_hospital_rounded,
  ),
  Clipart('hotel', Icons.hotel, Icons.hotel_outlined, Icons.hotel_rounded),
  Clipart('image', Icons.image, Icons.image_outlined, Icons.image_rounded),
  Clipart('key', Icons.key, Icons.key_outlined, Icons.key_rounded),
  Clipart(
    'language',
    Icons.language,
    Icons.language_outlined,
    Icons.language_rounded,
  ),
  Clipart(
    'lightbulb',
    Icons.lightbulb,
    Icons.lightbulb_outlined,
    Icons.lightbulb_rounded,
  ),
  Clipart('link', Icons.link, Icons.link_outlined, Icons.link_rounded),
  Clipart('lock', Icons.lock, Icons.lock_outlined, Icons.lock_rounded),
  Clipart('map', Icons.map, Icons.map_outlined, Icons.map_rounded),
  Clipart(
    'medication',
    Icons.medication,
    Icons.medication_outlined,
    Icons.medication_rounded,
  ),
  Clipart('memory', Icons.memory, Icons.memory_outlined, Icons.memory_rounded),
  Clipart(
    'menu_book',
    Icons.menu_book,
    Icons.menu_book_outlined,
    Icons.menu_book_rounded,
  ),
  Clipart('mic', Icons.mic, Icons.mic_outlined, Icons.mic_rounded),
  Clipart(
    'music',
    Icons.music_note,
    Icons.music_note_outlined,
    Icons.music_note_rounded,
  ),
  Clipart(
    'navigation',
    Icons.navigation,
    Icons.navigation_outlined,
    Icons.navigation_rounded,
  ),
  Clipart(
    'notifications',
    Icons.notifications,
    Icons.notifications_outlined,
    Icons.notifications_rounded,
  ),
  Clipart(
    'offer',
    Icons.local_offer,
    Icons.local_offer_outlined,
    Icons.local_offer_rounded,
  ),
  Clipart(
    'palette',
    Icons.palette,
    Icons.palette_outlined,
    Icons.palette_rounded,
  ),
  Clipart('person', Icons.person, Icons.person_outlined, Icons.person_rounded),
  Clipart('pets', Icons.pets, Icons.pets_outlined, Icons.pets_rounded),
  Clipart('phone', Icons.phone, Icons.phone_outlined, Icons.phone_rounded),
  Clipart('photo', Icons.photo, Icons.photo_outlined, Icons.photo_rounded),
  Clipart('pin', Icons.place, Icons.place_outlined, Icons.place_rounded),
  Clipart(
    'pizza',
    Icons.local_pizza,
    Icons.local_pizza_outlined,
    Icons.local_pizza_rounded,
  ),
  Clipart(
    'play',
    Icons.play_arrow,
    Icons.play_arrow_outlined,
    Icons.play_arrow_rounded,
  ),
  Clipart('public', Icons.public, Icons.public_outlined, Icons.public_rounded),
  Clipart(
    'qr_code',
    Icons.qr_code,
    Icons.qr_code_outlined,
    Icons.qr_code_rounded,
  ),
  Clipart(
    'real_estate',
    Icons.real_estate_agent,
    Icons.real_estate_agent_outlined,
    Icons.real_estate_agent_rounded,
  ),
  Clipart(
    'restaurant',
    Icons.restaurant,
    Icons.restaurant_outlined,
    Icons.restaurant_rounded,
  ),
  Clipart(
    'rocket',
    Icons.rocket_launch,
    Icons.rocket_launch_outlined,
    Icons.rocket_launch_rounded,
  ),
  Clipart(
    'run',
    Icons.directions_run,
    Icons.directions_run_outlined,
    Icons.directions_run_rounded,
  ),
  Clipart('school', Icons.school, Icons.school_outlined, Icons.school_rounded),
  Clipart('search', Icons.search, Icons.search_outlined, Icons.search_rounded),
  Clipart(
    'security',
    Icons.security,
    Icons.security_outlined,
    Icons.security_rounded,
  ),
  Clipart(
    'settings',
    Icons.settings,
    Icons.settings_outlined,
    Icons.settings_rounded,
  ),
  Clipart('shield', Icons.shield, Icons.shield_outlined, Icons.shield_rounded),
  Clipart(
    'shipping',
    Icons.local_shipping,
    Icons.local_shipping_outlined,
    Icons.local_shipping_rounded,
  ),
  Clipart(
    'shopping_bag',
    Icons.shopping_bag,
    Icons.shopping_bag_outlined,
    Icons.shopping_bag_rounded,
  ),
  Clipart(
    'soccer',
    Icons.sports_soccer,
    Icons.sports_soccer_outlined,
    Icons.sports_soccer_rounded,
  ),
  Clipart('spa', Icons.spa, Icons.spa_outlined, Icons.spa_rounded),
  Clipart('star', Icons.star, Icons.star_outlined, Icons.star_rounded),
  Clipart('store', Icons.store, Icons.store_outlined, Icons.store_rounded),
  Clipart(
    'sun',
    Icons.wb_sunny,
    Icons.wb_sunny_outlined,
    Icons.wb_sunny_rounded,
  ),
  Clipart(
    'task',
    Icons.task_alt,
    Icons.task_alt_outlined,
    Icons.task_alt_rounded,
  ),
  Clipart(
    'terminal',
    Icons.terminal,
    Icons.terminal_outlined,
    Icons.terminal_rounded,
  ),
  Clipart(
    'thumb_up',
    Icons.thumb_up,
    Icons.thumb_up_outlined,
    Icons.thumb_up_rounded,
  ),
  Clipart('train', Icons.train, Icons.train_outlined, Icons.train_rounded),
  Clipart('tv', Icons.tv, Icons.tv_outlined, Icons.tv_rounded),
  Clipart(
    'upload',
    Icons.cloud_upload,
    Icons.cloud_upload_outlined,
    Icons.cloud_upload_rounded,
  ),
  Clipart(
    'video',
    Icons.videocam,
    Icons.videocam_outlined,
    Icons.videocam_rounded,
  ),
  Clipart(
    'volunteer',
    Icons.volunteer_activism,
    Icons.volunteer_activism_outlined,
    Icons.volunteer_activism_rounded,
  ),
  Clipart(
    'water',
    Icons.water_drop,
    Icons.water_drop_outlined,
    Icons.water_drop_rounded,
  ),
  Clipart('wifi', Icons.wifi, Icons.wifi_outlined, Icons.wifi_rounded),
  Clipart('work', Icons.work, Icons.work_outlined, Icons.work_rounded),
];
