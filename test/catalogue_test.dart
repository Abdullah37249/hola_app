import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/data/local/local_trade_repository.dart';

void main() {
  // The GET /catalog/trade item HOLA sent (contract 0.7.5).
  final sample = {
    'productId': 'p1',
    'product': 'Hola Advanced Color Protection Shampoo',
    'brand': 'Hola Professional',
    'category': null,
    'imageUrl': 'https://cdn.shopify.com/s/files/Holacolorlockshampoo_4.webp',
    'variants': [
      {
        'id': 'v1',
        'sku': 'HOLA-53501365289298',
        'name': '1000 Ml',
        'shadeCode': null,
        'swatchHex': null,
        'tradePrice': '1650.00',
        'retailPrice': '2060.00',
        'inStock': true,
        'available': 24,
        'schemes': [
          {'id': 's0', 'name': '10% off', 'type': 'PERCENT_OFF', 'percentOff': 10, 'buyQty': null, 'freeQty': null, 'minQty': 5},
          {'id': 's1', 'name': 'Buy 10 get 1', 'type': 'BUY_X_GET_Y', 'percentOff': null, 'buyQty': 10, 'freeQty': 1, 'minQty': 10},
        ],
      },
    ],
  };

  test('a HOLA catalogue item becomes a product with photo, prices, stock and scheme', () {
    final p = mirrorProduct(sample, 0);
    expect(p.id, 'p1');
    expect(p.name, 'Hola Advanced Color Protection Shampoo');
    expect(p.category, 'Hair Care'); // no category from HOLA yet
    expect(p.imageUrl, startsWith('https://cdn.shopify.com/'));
    expect(p.hola, isTrue);
    expect(p.variants.single.name, '1000 Ml');
    expect(p.variants.single.tradePrice, 1650);
    expect(p.variants.single.retailPrice, 2060);
    expect(p.variants.single.stock, 24);
    expect((p.schemeBuy, p.schemeFree), (10, 1)); // percent-off schemes are not "buy X get Y"
    expect(p.freeFor(20), 2);
  });

  test('dashboard uploads, brand, SKU and size come through (0.28.0)', () {
    final p = mirrorProduct({
      'productId': 'p9',
      'product': 'Cream Activator',
      'brand': 'Hola Professional',
      'category': 'Colour',
      'imageUrl': 'https://hola.metaxperts.net/api/v1/public/files/f1',
      'imageUrls': ['https://hola.metaxperts.net/api/v1/public/files/f1', 'https://hola.metaxperts.net/api/v1/public/files/f2'],
      'variants': [
        {'id': 'v1', 'name': '10 Volume', 'sku': 'HCA-10', 'size': '1000 ML', 'tradePrice': '900.00', 'retailPrice': '1200.00', 'inStock': true},
      ],
    }, 0);
    expect(p.photos, hasLength(2));
    expect(p.photos.first, endsWith('/f1'));
    expect(p.brand, 'Hola Professional');
    expect(p.category, 'Colour');
    expect(p.variants.single.sku, 'HCA-10');
    expect(p.variants.single.size, '1000 ML');
  });
}
