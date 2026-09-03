using System;
using System.Collections.Generic;
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ModelBuilding;
using Microsoft.EntityFrameworkCore.Query;
using Microsoft.EntityFrameworkCore.Query.Translations;
using Microsoft.EntityFrameworkCore.Types;
using Microsoft.EntityFrameworkCore.Update;

namespace Pomelo.EntityFrameworkCore.MySql.FunctionalTests
{
    public class MySqlComplianceTest : RelationalComplianceTestBase
    {
        // TODO: Implement remaining 3.x tests.
        protected override ICollection<Type> IgnoredTestBases { get; } = new HashSet<Type>
        {
            // There are two classes that can lead to a MySqlEndOfStreamException, if *both* test classes are included in the run:
            //     - RelationalModelBuilderTest.RelationalComplexTypeTestBase
            //     - RelationalModelBuilderTest.RelationalOwnedTypesTestBase
            //
            // The exception is thrown for MySQL most of the time, though in rare cases also for MariaDB.
            // We disable `RelationalModelBuilderTest.RelationalOwnedTypesTestBase` for now.

            // typeof(RelationalModelBuilderTest.RelationalNonRelationshipTestBase),
            // typeof(RelationalModelBuilderTest.RelationalComplexTypeTestBase),
            // typeof(RelationalModelBuilderTest.RelationalInheritanceTestBase),
            // typeof(RelationalModelBuilderTest.RelationalOneToManyTestBase),
            // typeof(RelationalModelBuilderTest.RelationalManyToOneTestBase),
            // typeof(RelationalModelBuilderTest.RelationalOneToOneTestBase),
            // typeof(RelationalModelBuilderTest.RelationalManyToManyTestBase),
            typeof(RelationalModelBuilderTest.RelationalOwnedTypesTestBase),
            typeof(ModelBuilderTest.OwnedTypesTestBase), // base class of RelationalModelBuilderTest.RelationalOwnedTypesTestBase

            typeof(UdfDbFunctionTestBase<>),
            typeof(TransactionInterceptionTestBase),
            typeof(CommandInterceptionTestBase),
            typeof(NorthwindQueryTaggingQueryTestBase<>),

            // TODO: 9.0
            typeof(AdHocComplexTypeQueryTestBase),
            typeof(AdHocPrecompiledQueryRelationalTestBase),
            typeof(PrecompiledQueryRelationalTestBase),
            typeof(PrecompiledSqlPregenerationQueryRelationalTestBase),

            // TODO: Reenable LoggingMySqlTest once its issue has been fixed in EF Core upstream.
            typeof(LoggingTestBase),
            typeof(LoggingRelationalTestBase<,>),

            // We have our own JSON support for now
            typeof(AdHocJsonQueryTestBase),
            typeof(JsonQueryRelationalTestBase<>),
            typeof(JsonQueryTestBase<>),
            typeof(JsonTypesRelationalTestBase),
            typeof(JsonTypesTestBase),
            typeof(JsonUpdateTestBase<>),
            typeof(OptionalDependentQueryTestBase<>),

            // EF10-SPEC-DEFERRALS: every entry in this explicit EF Core 10 list is classified in
            // docs/efcore10-spec-deferrals.md. Existing provider-specific suites remain enabled; the
            // entries below are only the newly split bases without a reconciled concrete provider slice.
            // EF10-LAZYLOAD-RELATIONAL / EF10-COMPLEX-COLLECTIONS
            typeof(Microsoft.EntityFrameworkCore.LazyLoadProxyRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.ModelBuilding.ModelBuilderTest.ComplexCollectionTestBase),
            typeof(Microsoft.EntityFrameworkCore.ModelBuilding.RelationalModelBuilderTest.RelationalComplexCollectionTestBase),
            // EF10-JSON-ADHOC / EF10-JSON-COMPLEX-ASSOCIATIONS
            typeof(Microsoft.EntityFrameworkCore.Query.AdHocJsonQueryRelationalTestBase),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonBulkUpdateRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonCollectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonMiscellaneousRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonPrimitiveCollectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonProjectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonSetOperationsRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexJson.ComplexJsonStructuralEqualityRelationalTestBase<>),
            // EF10-COMPLEX-PROPERTIES / EF10-JSON-OWNED-ASSOCIATIONS
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexProperties.ComplexPropertiesCollectionTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.ComplexProperties.ComplexPropertiesSetOperationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonBulkUpdateRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonCollectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonMiscellaneousRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonPrimitiveCollectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonProjectionRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Associations.OwnedJson.OwnedJsonStructuralEqualityRelationalTestBase<>),
            // EF10-TRANSLATIONS / EF10-TEMPORAL-TRANSLATIONS / EF10-TYPES
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.MiscellaneousTranslationsRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Operators.ArithmeticOperatorTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Operators.BitwiseOperatorTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Operators.ComparisonOperatorTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Operators.LogicalOperatorTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Operators.MiscellaneousOperatorTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.StringTranslationsRelationalTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.StringTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateOnlyTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateTimeOffsetTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Temporal.DateTimeTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Temporal.TimeOnlyTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Query.Translations.Temporal.TimeSpanTranslationsTestBase<>),
            typeof(Microsoft.EntityFrameworkCore.Types.RelationalTypeTestBase<,>),

            // EF10-SPLIT-TRANSLATIONS: existing Northwind*/built-in type suites remain enabled while these
            // dedicated EF Core 10 split bases await provider-specific reconciliation.
            typeof(TypeTestBase<,>),
            typeof(ByteArrayTranslationsTestBase<>),
            typeof(EnumTranslationsTestBase<>),
            typeof(GuidTranslationsTestBase<>),
            typeof(MathTranslationsTestBase<>),
            typeof(MiscellaneousTranslationsTestBase<>),
        };

        protected override Assembly TargetAssembly { get; } = typeof(MySqlComplianceTest).Assembly;
    }
}
