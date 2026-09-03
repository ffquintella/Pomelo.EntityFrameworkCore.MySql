using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

var connectionString = Environment.GetEnvironmentVariable("POMELO_PACKAGE_CONSUMER_CONNECTION_STRING")
    ?? throw new InvalidOperationException("POMELO_PACKAGE_CONSUMER_CONNECTION_STRING is required.");

var serverType = Environment.GetEnvironmentVariable("POMELO_PACKAGE_CONSUMER_SERVER_TYPE")
    ?? throw new InvalidOperationException("POMELO_PACKAGE_CONSUMER_SERVER_TYPE is required.");

var serverVersion = ServerVersion.AutoDetect(connectionString);
if (!string.Equals(serverVersion.TypeIdentifier, serverType, StringComparison.OrdinalIgnoreCase))
{
    throw new InvalidOperationException(
        $"Expected a {serverType} server, but the connected server reported {serverVersion}.");
}

Console.WriteLine($"Package consumer: provider={typeof(MySqlDbContextOptionsBuilderExtensions).Assembly.GetName().Version}, " +
                  $"efcore={typeof(DbContext).Assembly.GetName().Version}, server={serverVersion}");

var packageAssemblies = new[]
{
    typeof(MySqlDbContextOptionsBuilderExtensions).Assembly,
    typeof(MySqlJsonMicrosoftDbContextOptionsBuilderExtensions).Assembly,
    typeof(MySqlJsonNewtonsoftDbContextOptionsBuilderExtensions).Assembly,
    typeof(MySqlNetTopologySuiteDbContextOptionsBuilderExtensions).Assembly
};

var expectedPackageNames = new[]
{
    "Pomelo.EntityFrameworkCore.MySql",
    "Pomelo.EntityFrameworkCore.MySql.Json.Microsoft",
    "Pomelo.EntityFrameworkCore.MySql.Json.Newtonsoft",
    "Pomelo.EntityFrameworkCore.MySql.NetTopologySuite"
};

if (!expectedPackageNames.All(expectedName => packageAssemblies.Any(assembly => assembly.GetName().Name == expectedName)))
{
    throw new InvalidOperationException("The four Pomelo package assemblies were not all loaded.");
}

Console.WriteLine($"Loaded Pomelo packages: {string.Join(", ", packageAssemblies.Select(assembly => assembly.GetName().Name))}");

// Compile and construct each public extension package through the package boundary.
var microsoftJsonOptions = new DbContextOptionsBuilder<SmokeContext>()
    .UseMySql(connectionString, serverVersion, options => options.UseMicrosoftJson())
    .Options;
var newtonsoftJsonOptions = new DbContextOptionsBuilder<SmokeContext>()
    .UseMySql(connectionString, serverVersion, options => options.UseNewtonsoftJson())
    .Options;
var netTopologySuiteOptions = new DbContextOptionsBuilder<SmokeContext>()
    .UseMySql(connectionString, serverVersion, options => options.UseNetTopologySuite())
    .Options;

AssertProviderRegistration(microsoftJsonOptions, "Microsoft JSON");
AssertProviderRegistration(newtonsoftJsonOptions, "Newtonsoft JSON");
AssertProviderRegistration(netTopologySuiteOptions, "NetTopologySuite");

var optionsBuilder = new DbContextOptionsBuilder<SmokeContext>()
    .UseMySql(connectionString, serverVersion);

var committedItemId = 0;

await using (var context = new SmokeContext(optionsBuilder.Options))
{
    var appliedMigrations = context.Database.GetAppliedMigrations().ToArray();
    if (appliedMigrations.Length != 1)
    {
        throw new InvalidOperationException(
            $"Expected one migration to be applied by the public CLI, found {appliedMigrations.Length}.");
    }

    await using var transaction = await context.Database.BeginTransactionAsync();

    var item = new SmokeItem { Name = "created" };
    context.Items.Add(item);
    await context.SaveChangesAsync();

    if (item.Id <= 0)
    {
        throw new InvalidOperationException("The database did not generate an identity key.");
    }

    item.Name = "updated";
    await context.SaveChangesAsync();

    var updated = await context.Items
        .Where(candidate => candidate.Id == item.Id)
        .SingleAsync();
    if (updated.Name != "updated")
    {
        throw new InvalidOperationException("The update round trip returned an unexpected value.");
    }

    await transaction.CommitAsync();
    committedItemId = updated.Id;
}

await using (var context = new SmokeContext(optionsBuilder.Options))
{
    var committed = await context.Items.SingleOrDefaultAsync(item => item.Id == committedItemId);
    if (committed is null || committed.Name != "updated")
    {
        throw new InvalidOperationException("The committed row was not visible from a new context.");
    }

    context.Items.Remove(committed);
    await context.SaveChangesAsync();
}

await using (var context = new SmokeContext(optionsBuilder.Options))
{
    if (await context.Items.AnyAsync())
    {
        throw new InvalidOperationException("The delete round trip left rows in the database.");
    }
}

Console.WriteLine("Package consumer smoke passed: model creation, CRUD, and transaction commit.");

static void AssertProviderRegistration(DbContextOptions<SmokeContext> options, string extensionName)
{
    using var context = new SmokeContext(options);
    if (context.Database.ProviderName != "Pomelo.EntityFrameworkCore.MySql")
    {
        throw new InvalidOperationException($"The {extensionName} options were not registered with Pomelo.");
    }
}

public sealed class SmokeContext(DbContextOptions<SmokeContext> options) : DbContext(options)
{
    public DbSet<SmokeItem> Items => Set<SmokeItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
        => modelBuilder.Entity<SmokeItem>(entity =>
        {
            entity.ToTable("PackageConsumerItems");
            entity.HasKey(item => item.Id);
            entity.Property(item => item.Name).HasMaxLength(64).IsRequired();
        });
}

public sealed class SmokeContextFactory : IDesignTimeDbContextFactory<SmokeContext>
{
    public SmokeContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("POMELO_PACKAGE_CONSUMER_CONNECTION_STRING")
            ?? throw new InvalidOperationException("POMELO_PACKAGE_CONSUMER_CONNECTION_STRING is required.");

        var serverVersion = ServerVersion.AutoDetect(connectionString);
        var options = new DbContextOptionsBuilder<SmokeContext>()
            .UseMySql(connectionString, serverVersion)
            .Options;

        return new SmokeContext(options);
    }
}

public sealed class SmokeItem
{
    public int Id { get; set; }

    public string Name { get; set; } = null!;
}
