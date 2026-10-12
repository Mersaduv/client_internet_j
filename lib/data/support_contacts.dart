/// شماره‌های پشتیبانی بر اساس ولایت — مشترک بین لاگین و امور مشترکین
class SupportPhoneLine {
  const SupportPhoneLine({
    required this.number,
    required this.roleFa,
    required this.roleEn,
  });

  final String number;
  final String roleFa;
  final String roleEn;

  String role({required bool english}) => english ? roleEn : roleFa;
}

class ProvinceSupportContacts {
  const ProvinceSupportContacts({
    required this.nameFa,
    required this.nameEn,
    required this.phones,
  });

  final String nameFa;
  final String nameEn;
  final List<SupportPhoneLine> phones;

  String name({required bool english}) => english ? nameEn : nameFa;
}

class SupportContacts {
  SupportContacts._();

  static const List<ProvinceSupportContacts> provinces = [
    ProvinceSupportContacts(
      nameFa: 'هرات',
      nameEn: 'Herat',
      phones: [
        SupportPhoneLine(
          number: '0795223279',
          roleFa: 'فروشات',
          roleEn: 'Sales',
        ),
        SupportPhoneLine(
          number: '0799120543',
          roleFa: 'خدمات',
          roleEn: 'Services',
        ),
      ],
    ),
    ProvinceSupportContacts(
      nameFa: 'نیمروز',
      nameEn: 'Nimroz',
      phones: [
        SupportPhoneLine(
          number: '0799205444',
          roleFa: 'فروشات',
          roleEn: 'Sales',
        ),
        SupportPhoneLine(
          number: '0799161150',
          roleFa: 'خدمات',
          roleEn: 'Services',
        ),
      ],
    ),
    ProvinceSupportContacts(
      nameFa: 'فراه',
      nameEn: 'Farah',
      phones: [
        SupportPhoneLine(
          number: '0792979691',
          roleFa: 'فروشات',
          roleEn: 'Sales',
        ),
        SupportPhoneLine(
          number: '0795336608',
          roleFa: 'خدمات',
          roleEn: 'Services',
        ),
      ],
    ),
  ];
}
