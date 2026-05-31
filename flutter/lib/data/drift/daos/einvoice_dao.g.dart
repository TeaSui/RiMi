// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'einvoice_dao.dart';

// ignore_for_file: type=lint
mixin _$EinvoiceDaoMixin on DatabaseAccessor<AppDatabase> {
  $InvoicesTable get invoices => attachedDatabase.invoices;
  EinvoiceDaoManager get managers => EinvoiceDaoManager(this);
}

class EinvoiceDaoManager {
  final _$EinvoiceDaoMixin _db;
  EinvoiceDaoManager(this._db);
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
}
