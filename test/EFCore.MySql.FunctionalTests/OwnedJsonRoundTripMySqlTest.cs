// Copyright (c) Pomelo Foundation. All rights reserved.
// Licensed under the MIT License. See LICENSE in the project root for license information.

using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.TestUtilities;
using Pomelo.EntityFrameworkCore.MySql.FunctionalTests.TestUtilities;
using Xunit;

namespace Pomelo.EntityFrameworkCore.MySql.FunctionalTests;

public class OwnedJsonRoundTripMySqlTest
    : OwnedJsonRoundTripTestBase<OwnedJsonRoundTripMySqlTest.MySqlFixture>
{
    public OwnedJsonRoundTripMySqlTest(MySqlFixture fixture)
        : base(fixture)
    {
    }

    public sealed class MySqlFixture : OwnedJsonRoundTripFixtureBase
    {
        protected override ITestStoreFactory TestStoreFactory
            => MySqlTestStoreFactory.Instance;
    }
}

public class OwnedJsonRoundTripMySqlNoBackslashEscapesTest
    : OwnedJsonRoundTripTestBase<OwnedJsonRoundTripMySqlNoBackslashEscapesTest.MySqlFixture>
{
    public OwnedJsonRoundTripMySqlNoBackslashEscapesTest(MySqlFixture fixture)
        : base(fixture)
    {
    }

    public sealed class MySqlFixture : OwnedJsonRoundTripFixtureBase
    {
        protected override string StoreName
            => "OwnedJsonRoundTripNBE";

        protected override ITestStoreFactory TestStoreFactory
            => MySqlTestStoreFactory.NoBackslashEscapesInstance;
    }
}

public abstract class OwnedJsonRoundTripTestBase<TFixture>(TFixture fixture)
    : IClassFixture<TFixture>
    where TFixture : OwnedJsonRoundTripFixtureBase, new()
{
    private const string InitialDescription = "O'Reilly \\ archive — 初始 😀";
    private const string UpdatedDescription = "\"quoted\" \\ updated — 更新 🧪";

    protected TFixture Fixture { get; } = fixture;

    [Fact]
    public async Task Owned_json_value_round_trips_and_updates()
    {
        await using (var context = Fixture.CreateContext())
        {
            var document = await context.Documents.SingleAsync(
                candidate => candidate.Settings.Description == InitialDescription);

            Assert.Equal(InitialDescription, document.Settings!.Description);
            document.Settings.Description = UpdatedDescription;

            await context.SaveChangesAsync();
        }

        await using (var context = Fixture.CreateContext())
        {
            var updatedDocument = await context.Documents.SingleAsync(
                candidate => candidate.Settings.Description == UpdatedDescription);

            Assert.Equal(UpdatedDescription, updatedDocument.Settings!.Description);
            updatedDocument.Settings.Description = string.Empty;

            await context.SaveChangesAsync();
        }

        await using var verificationContext = Fixture.CreateContext();
        var emptyDocument = await verificationContext.Documents.SingleAsync(
            candidate => candidate.Settings.Description == string.Empty);

        Assert.Equal(string.Empty, emptyDocument.Settings!.Description);
    }
}

public abstract class OwnedJsonRoundTripFixtureBase
    : SharedStoreFixtureBase<OwnedJsonRoundTripContext>
{
    protected override string StoreName
        => "OwnedJsonRoundTripMySqlTest";

    protected override Task SeedAsync(OwnedJsonRoundTripContext context)
    {
        context.Documents.Add(
            new OwnedJsonRoundTripDocument
            {
                Id = 1,
                Settings = new OwnedJsonRoundTripSettings { Description = "O'Reilly \\ archive — 初始 😀" }
            });

        return context.SaveChangesAsync();
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder, DbContext context)
        => modelBuilder.Entity<OwnedJsonRoundTripDocument>(builder =>
        {
            builder.Property(document => document.Id).ValueGeneratedNever();
            builder.OwnsOne(
                document => document.Settings,
                ownedBuilder => ownedBuilder.ToJson());
        });
}

public sealed class OwnedJsonRoundTripContext(DbContextOptions options) : DbContext(options)
{
    public DbSet<OwnedJsonRoundTripDocument> Documents
        => Set<OwnedJsonRoundTripDocument>();
}

public sealed class OwnedJsonRoundTripDocument
{
    public int Id { get; set; }
    public OwnedJsonRoundTripSettings Settings { get; set; } = null!;
}

public sealed class OwnedJsonRoundTripSettings
{
    public string Description { get; set; } = null!;
}
