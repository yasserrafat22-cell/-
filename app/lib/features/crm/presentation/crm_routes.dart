import '../domain/crm_models.dart';

/// مسارات شاشات العملاء والموردين.
abstract final class CrmRoutes {
  static const newCustomer = '/customers/new';
  static const newSupplier = '/suppliers/new';
  static const partyPattern = '/parties/:id';
  static const catalog = '/catalog';

  static String party(String id, {bool? supplier}) =>
      '/parties/$id${supplier == null ? '' : '?role=${supplier ? 'supplier' : 'customer'}'}';
  static String newOrder(String id) => '/parties/$id/order';
  static String newSupply(String id) => '/parties/$id/supply';
  static String editDetails(String id) => '/parties/$id/edit';

  static String newContact(String id, {ContactChannel? channel}) =>
      '/parties/$id/contact${channel == null ? '' : '?channel=${channel.name}'}';
}
