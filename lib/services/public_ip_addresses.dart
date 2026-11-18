class PublicIPAddresses {
  final String? ipv4;
  final String? ipv6;

  const PublicIPAddresses({this.ipv4, this.ipv6});

  String? get primary => ipv6 ?? ipv4;
}
