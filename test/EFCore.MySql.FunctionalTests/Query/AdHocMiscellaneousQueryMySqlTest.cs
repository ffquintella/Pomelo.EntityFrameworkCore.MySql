using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Query;
using Microsoft.EntityFrameworkCore.TestUtilities;
using NameSpace1;
using Pomelo.EntityFrameworkCore.MySql.FunctionalTests.TestUtilities;
using Pomelo.EntityFrameworkCore.MySql.Infrastructure;
using Pomelo.EntityFrameworkCore.MySql.Tests.TestUtilities.Attributes;
using Xunit;

namespace Pomelo.EntityFrameworkCore.MySql.FunctionalTests.Query;

public class AdHocMiscellaneousQueryMySqlTest(NonSharedFixture fixture) : AdHocMiscellaneousQueryRelationalTestBase(fixture)
{
    protected override ITestStoreFactory TestStoreFactory
        => MySqlTestStoreFactory.Instance;

    protected override DbContextOptionsBuilder SetParameterizedCollectionMode(
        DbContextOptionsBuilder optionsBuilder,
        ParameterTranslationMode parameterizedCollectionMode)
    {
        new MySqlDbContextOptionsBuilder(optionsBuilder).UseParameterizedCollectionMode(parameterizedCollectionMode);

        return optionsBuilder;
    }

    protected override Task Seed2951(Context2951 context)
        => context.Database.ExecuteSqlRawAsync(
            """
CREATE TABLE `ZeroKey` (`Id` int);
INSERT INTO `ZeroKey` VALUES (NULL)
""");

    public override async Task Multiple_different_entity_type_from_different_namespaces(bool async)
    {
        // The only change is the FromSqlRaw SQL string:
        //     Original: SELECT cast(null as int) AS MyValue
        //     Changed:  SELECT cast(null as signed) AS MyValue
        // The other comments are part of the base implementation.

        var contextFactory = await InitializeAsync<Context23981>();
        using var context = contextFactory.CreateContext();
        //var good1 = context.Set<NameSpace1.TestQuery>().FromSqlRaw(@"SELECT 1 AS MyValue").ToList(); // OK
        //var good2 = context.Set<NameSpace2.TestQuery>().FromSqlRaw(@"SELECT 1 AS MyValue").ToList(); // OK
        var bad = context.Set<TestQuery>().FromSqlRaw(@"SELECT cast(null as signed) AS MyValue").ToList(); // Exception
    }

    [ConditionalFact]
    public async Task Nested_Skip_Take_does_not_emit_LEAST_or_GREATEST_in_limit_offset()
    {
        var contextFactory = await InitializeAsync<LimitOffsetContext>(seed: c => c.SeedAsync());
        using var context = contextFactory.CreateContext();

        // Use captured variables so that Skip/Take are translated to query parameters rather than constants.
        // Under EF Core 10, composing Take over an existing Skip/Take produces a LEAST(...) expression in the
        // LIMIT clause (GREATEST is produced by analogous compositions and handled by the same code path).
        // MySQL and MariaDB reject function expressions in LIMIT/OFFSET, so the provider must evaluate them to
        // a constant at execution time (MySqlLimitOffsetInliningExpressionVisitor).
        var skip = 1;
        var take1 = 6;
        var take2 = 3;

        var result = await context.Set<LimitOffsetEntity>()
            .OrderBy(e => e.Id)
            .Skip(skip).Take(take1)
            .Take(take2)
            .Select(e => e.Id)
            .ToListAsync();

        // Executing successfully against MySQL/MariaDB already proves no LEAST/GREATEST reached the LIMIT/OFFSET
        // clauses (the database would otherwise reject the statement with "Undeclared variable: LEAST"); assert
        // the generated SQL explicitly too.
        var sql = TestSqlLoggerFactory.SqlStatements.Last();
        Assert.DoesNotContain("LEAST", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GREATEST", sql, StringComparison.OrdinalIgnoreCase);

        // Skip(1).Take(6) -> ids 2..7; .Take(3) -> first three -> ids 2, 3, 4.
        Assert.Equal(new[] { 2, 3, 4 }, result);
    }

    [ConditionalFact]
    public async Task Nested_Skip_Take_uses_current_values_for_each_execution()
    {
        var contextFactory = await InitializeAsync<LimitOffsetContext>(seed: c => c.SeedAsync());
        using var context = contextFactory.CreateContext();

        var skip = 1;
        var take1 = 6;
        var take2 = 3;

        IQueryable<int> Query()
            => context.Set<LimitOffsetEntity>()
                .OrderBy(e => e.Id)
                .Skip(skip).Take(take1)
                .Take(take2)
                .Select(e => e.Id);

        var first = await Query().ToListAsync();

        skip = 4;
        take1 = 4;
        take2 = 2;

        var second = await Query().ToListAsync();

        Assert.Equal(new[] { 2, 3, 4 }, first);
        Assert.Equal(new[] { 5, 6 }, second);

        var sql = TestSqlLoggerFactory.SqlStatements.Last();
        Assert.DoesNotContain("LEAST", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GREATEST", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("@p='4'", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("LIMIT 2", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("LIMIT 3", sql, StringComparison.OrdinalIgnoreCase);
    }

    [ConditionalFact]
    public async Task String_comparison_runtime_parameter_uses_current_value_for_each_execution()
    {
        var contextFactory = await InitializeAsync<LimitOffsetContext>(
            seed: c => c.SeedAsync(),
            onConfiguring: b => new MySqlDbContextOptionsBuilder(b).EnableStringComparisonTranslations());
        using var context = contextFactory.CreateContext();

        var pattern = "1";

        IQueryable<int> Query()
            => context.Set<LimitOffsetEntity>()
                .Where(e => e.Name.Contains(pattern, StringComparison.OrdinalIgnoreCase))
                .OrderBy(e => e.Id)
                .Select(e => e.Id);

        var first = await Query().ToListAsync();

        pattern = "2";
        var second = await Query().ToListAsync();

        Assert.Equal(new[] { 1, 10 }, first);
        Assert.Equal(new[] { 2 }, second);

        var sql = TestSqlLoggerFactory.SqlStatements.Last();
        Assert.Contains("LIKE", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("'%2%'", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("'%1%'", sql, StringComparison.OrdinalIgnoreCase);
    }

    [ConditionalFact]
    public Task Parameterized_collection_uses_current_values_for_each_execution()
        => Parameterized_collection_uses_current_values_for_each_execution_core(ParameterTranslationMode.Constant);

    [ConditionalTheory]
    [SupportedServerVersionCondition(nameof(ServerVersionSupport.JsonTable))]
    [InlineData(ParameterTranslationMode.Parameter)]
    public Task Parameterized_collection_uses_current_values_for_each_execution_parameter(ParameterTranslationMode mode)
        => Parameterized_collection_uses_current_values_for_each_execution_core(mode);

    private async Task Parameterized_collection_uses_current_values_for_each_execution_core(ParameterTranslationMode mode)
    {
        var contextFactory = await InitializeAsync<PrimitiveCollectionContext>(
            seed: c => c.SeedAsync(),
            onConfiguring: b => new MySqlDbContextOptionsBuilder(b)
                .UseParameterizedCollectionMode(mode),
            usePooling: false);
        using var context = contextFactory.CreateContext();

        var ids = new[] { 2, 3 };

        IQueryable<int> Query()
            => context.Set<LimitOffsetEntity>()
                .Where(e => ids.Contains(e.Id))
                .OrderBy(e => e.Id)
                .Select(e => e.Id);

        var first = await Query().ToListAsync();

        ids = new[] { 5, 6 };
        var second = await Query().ToListAsync();

        Assert.Equal(new[] { 2, 3 }, first);
        Assert.Equal(new[] { 5, 6 }, second);

        var sql = TestSqlLoggerFactory.SqlStatements.Last();
        switch (mode)
        {
            case ParameterTranslationMode.Constant:
                Assert.Contains("IN (5, 6)", sql, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain("IN (2, 3)", sql, StringComparison.OrdinalIgnoreCase);
                break;

            case ParameterTranslationMode.Parameter:
                Assert.Contains("JSON_TABLE('[5,6]'", sql, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain("JSON_TABLE('[2,3]'", sql, StringComparison.OrdinalIgnoreCase);
                break;

            default:
                throw new ArgumentOutOfRangeException(nameof(mode), mode, null);
        }
    }

    private class LimitOffsetEntity
    {
        public int Id { get; set; }
        public string Name { get; set; }
    }

    private class LimitOffsetContext(DbContextOptions options) : DbContext(options)
    {
        public DbSet<LimitOffsetEntity> Entities { get; set; }

        public Task SeedAsync()
        {
            AddRange(Enumerable.Range(1, 10).Select(i => new LimitOffsetEntity { Id = i, Name = "Name" + i }));
            return SaveChangesAsync();
        }
    }

    private class PrimitiveCollectionContext(DbContextOptions options) : LimitOffsetContext(options)
    {
        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            base.OnConfiguring(optionsBuilder);
            new MySqlDbContextOptionsBuilder(optionsBuilder).EnablePrimitiveCollectionsSupport();
        }
    }
}
