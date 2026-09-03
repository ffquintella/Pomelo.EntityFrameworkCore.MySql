# EF Core 10 specification coverage and deferrals

Status: audited against `8f5f1d74f4426916473722ae22e7aff5cb4c003e`.

This ledger is the public record for EF Core 10 specification suites that are
not represented by a concrete Pomelo test class yet, and for the method-level
deferrals introduced while the EF Core 10 provider work was reconciled. It is
intentionally separate from the provider's historical skip inventory. Existing
Pomelo 9 coverage remains enabled; an EF Core 10 base is listed here only when
the corresponding split suite still needs a provider implementation or a
server-specific proof.

The audit is executable from any working directory:

```text
test/EFCore.MySql.FunctionalTests/audit-efcore10-spec-coverage.sh
```

The check uses the immutable main baseline `14c2cd558e37c71e7a2fca75e339ef902effdf60`,
so it detects newly introduced method-level skips without sweeping the
repository's historical skips. The table records all 39 EF Core 10 base
ignores and the 14 method-level skip additions relative to that baseline.
Every entry has one of four classifications:

- `database-native`: a server or connector limitation is the reason for the
  deferral and the evidence names the capability.
- `upstream issue`: behavior is tracked by an EF Core issue.
- `historically unsupported`: the provider has not exposed this workflow in a
  supported release and the history is part of the reason for retaining the
  deferral.
- `explicit follow-up`: provider work or a dedicated EF Core 10 test slice is
  still required; the reference is the stable follow-up identifier.

The broad EF Core 10 entries below are explicit, finite deferrals. They do not
disable the existing provider-specific association, primitive collection,
spatial, temporal, numeric, string, or inheritance suites. Those suites are
run with the MySQL/MariaDB server-version conditions already present in their
concrete tests. In particular, MariaDB LATERAL and MySQL/MariaDB precision
limitations stay narrow method or capability conditions rather than class-wide
ignores.

| Kind | Stable source key | Classification | Owner | Follow-up/reference | Evidence and boundary |
| --- | --- | --- | --- | --- | --- |
| base | Microsoft.EntityFrameworkCore.LazyLoadProxyRelationalTestBase<> | explicit follow-up | Provider test maintainers | EF10-LAZYLOAD-RELATIONAL | `LazyLoadProxyMySqlTest` covers the existing non-relational provider base; the new relational split base has no concrete Pomelo subclass. |
| base | Microsoft.EntityFrameworkCore.ModelBuilding.ModelBuilderTest.ComplexCollectionTestBase | explicit follow-up | Provider model-building maintainers | EF10-COMPLEX-COLLECTIONS | Existing model-building tests remain enabled; the EF Core 10 complex-collection split suite needs a provider-specific implementation. |
| base | Microsoft.EntityFrameworkCore.ModelBuilding.RelationalModelBuilderTest.RelationalComplexCollectionTestBase | explicit follow-up | Provider model-building maintainers | EF10-COMPLEX-COLLECTIONS | Existing relational model-building tests remain enabled; this newly split EF Core 10 suite has no concrete Pomelo implementation. |
| base | Microsoft.EntityFrameworkCore.Query.AdHocJsonQueryRelationalTestBase | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-ADHOC | Structural JSON persistence and query tests are enabled separately; the broad ad-hoc relational suite still needs a provider slice. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonBulkUpdateRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Structural JSON bulk-update coverage is kept in focused provider tests; the split association suite remains a follow-up. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonCollectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Structural JSON collection coverage is kept in focused provider tests; the split association suite remains a follow-up. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonMiscellaneousRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Focused JSON miscellaneous behavior is covered where supported; the broad split suite needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonPrimitiveCollectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Primitive collections inside structural JSON are a separate provider follow-up, not a blanket query exclusion. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonProjectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Focused JSON projections are enabled; this newly split relational association suite remains unimplemented. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonSetOperationsRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Set-operation behavior over complex JSON associations needs a dedicated provider baseline. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonStructuralEqualityRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-COMPLEX-ASSOCIATIONS | Focused structural JSON equality coverage is enabled; this split suite needs independent reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexProperties.ComplexPropertiesCollectionTestBase<> | explicit follow-up | Provider complex-property maintainers | EF10-COMPLEX-PROPERTIES | Concrete complex-property collection coverage is not yet reconciled for the EF Core 10 split suite. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.ComplexProperties.ComplexPropertiesSetOperationsTestBase<> | explicit follow-up | Provider complex-property maintainers | EF10-COMPLEX-PROPERTIES | Complex-property set operations need a provider-specific EF Core 10 baseline. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonBulkUpdateRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Focused owned JSON update coverage is enabled; the split relational association suite remains a follow-up. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonCollectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Focused owned JSON collection coverage is enabled; this broad suite needs provider reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonMiscellaneousRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Owned JSON miscellaneous behavior needs a dedicated provider baseline. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonPrimitiveCollectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Primitive collections in owned JSON remain a narrow structural JSON follow-up. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonProjectionRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Focused owned JSON projections are enabled; this split suite still needs provider baselines. |
| base | Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonStructuralEqualityRelationalTestBase<> | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-OWNED-ASSOCIATIONS | Owned JSON structural equality needs a provider-specific EF Core 10 test slice. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.MiscellaneousTranslationsRelationalTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing Northwind and provider translation suites remain enabled; this newly split EF Core 10 base needs coverage. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Operators.ArithmeticOperatorTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing arithmetic translation coverage remains enabled; the dedicated EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Operators.BitwiseOperatorTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing bitwise translation coverage remains enabled; the dedicated EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Operators.ComparisonOperatorTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing comparison translation coverage remains enabled; the dedicated EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Operators.LogicalOperatorTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing logical translation coverage remains enabled; the dedicated EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Operators.MiscellaneousOperatorTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing operator coverage remains enabled; the dedicated EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.StringTranslationsRelationalTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing string translation suites remain enabled; the new relational split base needs provider baselines. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.StringTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-TRANSLATIONS | Existing provider string suites remain enabled; this new EF Core 10 base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateOnlyTranslationsTestBase<> | explicit follow-up | Provider temporal maintainers | EF10-TEMPORAL-TRANSLATIONS | DateOnly provider tests remain enabled; the dedicated EF Core 10 translation base needs a server-aware baseline. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateTimeOffsetTranslationsTestBase<> | explicit follow-up | Provider temporal maintainers | EF10-TEMPORAL-TRANSLATIONS | DateTimeOffset provider tests remain enabled; the dedicated EF Core 10 translation base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateTimeTranslationsTestBase<> | explicit follow-up | Provider temporal maintainers | EF10-TEMPORAL-TRANSLATIONS | DateTime provider tests remain enabled; the dedicated EF Core 10 translation base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Temporal.TimeOnlyTranslationsTestBase<> | explicit follow-up | Provider temporal maintainers | EF10-TEMPORAL-TRANSLATIONS | TimeOnly provider tests remain enabled; the dedicated EF Core 10 translation base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Query.Translations.Temporal.TimeSpanTranslationsTestBase<> | explicit follow-up | Provider temporal maintainers | EF10-TEMPORAL-TRANSLATIONS | TimeSpan provider tests remain enabled; the dedicated EF Core 10 translation base needs reconciliation. |
| base | Microsoft.EntityFrameworkCore.Types.RelationalTypeTestBase<,> | explicit follow-up | Provider type-mapping maintainers | EF10-TYPES | Existing built-in type and mapping suites remain enabled; this dedicated relational type base needs coverage. |
| base | TypeTestBase<,> | explicit follow-up | Provider type-mapping maintainers | EF10-SPLIT-TRANSLATIONS | Existing built-in type suites remain enabled; the EF Core 10 split type base needs reconciliation. |
| base | ByteArrayTranslationsTestBase<> | explicit follow-up | Provider type-mapping maintainers | EF10-SPLIT-TRANSLATIONS | Existing byte-array coverage remains enabled; this newly split translation base needs a provider baseline. |
| base | EnumTranslationsTestBase<> | explicit follow-up | Provider type-mapping maintainers | EF10-SPLIT-TRANSLATIONS | Existing enum coverage remains enabled; this newly split translation base needs a provider baseline. |
| base | GuidTranslationsTestBase<> | explicit follow-up | Provider type-mapping maintainers | EF10-SPLIT-TRANSLATIONS | Existing GUID coverage remains enabled; this newly split translation base needs a provider baseline. |
| base | MathTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-SPLIT-TRANSLATIONS | Existing math translation coverage remains enabled; this newly split base needs reconciliation. |
| base | MiscellaneousTranslationsTestBase<> | explicit follow-up | Provider translation maintainers | EF10-SPLIT-TRANSLATIONS | Existing miscellaneous translation coverage remains enabled; this newly split base needs reconciliation. |
| method | test/EFCore.MySql.FunctionalTests/LazyLoadProxyMySqlTest.cs#Top_level_projection_track_entities_before_passing_to_client_method() | explicit follow-up | Provider test maintainers | EF10-LAZYLOAD-PROJECTION | Provider lazy-loading identity behavior differs for this projection; the rest of the concrete suite remains enabled. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsInfrastructureMySqlTest.cs#Can_apply_two_migrations_in_transaction_async() | database-native | Migration test maintainers | MYSQL-DDL-IMPLICIT-COMMIT | MySQL implicitly commits DDL, so this transaction-specific scenario is narrow and not a class-wide migration skip. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Convert_string_column_to_a_json_column_containing_collection() | explicit follow-up | Provider migration maintainers | EF10-JSON-MIGRATION-CONVERSION | Converting populated string data to a JSON collection is not supported by the current mapping. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Convert_string_column_to_a_json_column_containing_reference() | explicit follow-up | Provider migration maintainers | EF10-JSON-MIGRATION-CONVERSION | Converting populated string data to a JSON reference is not supported by the current mapping. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Multiop_rename_table_and_create_new_table_with_the_old_name() | historically unsupported | Provider migration maintainers | EF10-MIGRATION-PK-PROCEDURES | The multi-operation path depends on primary-key recreation procedures not exposed by the provider. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Multiop_rename_table_and_drop() | historically unsupported | Provider migration maintainers | EF10-MIGRATION-PK-PROCEDURES | The multi-operation path depends on primary-key recreation procedures not exposed by the provider. |
| method | test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Rename_table_with_json_column() | historically unsupported | Provider migration maintainers | EF10-MIGRATION-PK-PROCEDURES | Renaming this JSON table exercises the provider's unsupported primary-key stored-procedure path. |
| method | test/EFCore.MySql.FunctionalTests/Query/AdHocQuerySplittingQueryMySqlTest.cs#Can_query_with_nav_collection_in_projection_with_split_query_in_parallel_async() | explicit follow-up | Provider query maintainers | EF10-SPLIT-PROJECTION | Parallel split-query navigation projection is not currently translated on MySQL. |
| method | test/EFCore.MySql.FunctionalTests/Query/AdHocQuerySplittingQueryMySqlTest.cs#Can_query_with_nav_collection_in_projection_with_split_query_in_parallel_sync() | explicit follow-up | Provider query maintainers | EF10-SPLIT-PROJECTION | Parallel split-query navigation projection is not currently translated on MySQL. |
| method | test/EFCore.MySql.FunctionalTests/Query/FromSqlQueryMySqlTest.cs#Multiple_occurrences_of_FromSql_with_db_parameter_adds_two_parameters(bool async) | database-native | Provider connector maintainers | MYSQLCONNECTOR-PARAMETER-REUSE | Reusing one DbParameter across FromSql occurrences has different MySqlConnector behavior. |
| method | test/EFCore.MySql.FunctionalTests/Query/NonSharedPrimitiveCollectionsQueryMySqlTest.cs#Column_collection_inside_json_owned_entity() | explicit follow-up | Provider JSON/query maintainers | EF10-JSON-PRIMITIVE-COLLECTION | Primitive collection translation nested in a JSON-owned document is outside the current structural JSON slice. |
| method | test/EFCore.MySql.FunctionalTests/Query/NorthwindMiscellaneousQueryMySqlTest.cs#Where_nanosecond_and_microsecond_component(bool async) | database-native | Provider temporal maintainers | MYSQL-MARIADB-DATETIME-6 | MySQL and MariaDB store DATETIME with microsecond precision at most; nanoseconds have no server representation. |
| method | test/EFCore.MySql.FunctionalTests/Query/PrimitiveCollectionsQueryMySqlTest.cs#Inline_collection_index_Column_with_EF_Constant() | database-native | Provider query maintainers | MYSQL-MARIADB-LIMIT-OFFSET | MySQL and MariaDB do not allow a column or expression in LIMIT/OFFSET. |
| method | test/EFCore.MySql.FunctionalTests/Query/SqlQueryMySqlTest.cs#Multiple_occurrences_of_SqlQuery_with_db_parameter_adds_two_parameters(bool async) | database-native | Provider connector maintainers | MYSQLCONNECTOR-PARAMETER-REUSE | Reusing one DbParameter across SqlQuery occurrences has different MySqlConnector behavior. |
