using System;
using System.Linq;
using Microsoft.EntityFrameworkCore;

namespace Pomelo.EntityFrameworkCore.MySql.IntegrationTests.Commands{

    public class CommandRunner : ICommandRunner
    {

        private IConnectionStringCommand _connectionStringCommand;
        private ITestMigrateCommand _testMigrateCommand;
        private ITestPerformanceCommand _testPerformanceCommand;

        public CommandRunner(
            IConnectionStringCommand connectionStringCommand,
            ITestMigrateCommand testMigrateCommand,
            ITestPerformanceCommand testPerformanceCommand
        )
        {
            _connectionStringCommand = connectionStringCommand;
            _testMigrateCommand = testMigrateCommand;
            _testPerformanceCommand = testPerformanceCommand;
        }

        public void Help()
        {
            Console.Error.WriteLine(@"dotnet run
    connectionString   print connection string
    testMigrate        test dbContext.Database functions: ensureCreate, ensureDelete, migrate
    compiledModel      load the generated compiled model and execute a query
    testPerformance [iterations] [concurrency] [operations]
    -h, --help         show this message
            ");
        }

        public int Run(string[] args)
        {
            var cmd = args[0];

            try
            {
	            switch (cmd)
	            {
		            case "connectionString":
                        _connectionStringCommand.Run();
			            break;
                    case "testMigrate":
                        _testMigrateCommand.Run();
			            break;
                    case "compiledModel":
                        using (var scope = new AppDbScope())
                        {
                            var db = scope.AppDb;
                            if (db.Model.GetType().FullName != "Pomelo.EntityFrameworkCore.MySql.IntegrationTests.Optimize.AppDbModel")
                            {
                                throw new InvalidOperationException($"The generated compiled model was not loaded. Actual model: {db.Model.GetType().FullName}");
                            }

                            db.DataTypesSimple
                                .AsNoTracking()
                                .Select(e => e.Id)
                                .Take(1)
                                .ToList();
                        }
                        break;
	                case "testPerformance":
	                    if (args.Length != 4)
                        {
                            goto default;
                        }

                        _testPerformanceCommand.Run(int.Parse(args[1]), int.Parse(args[2]), int.Parse(args[3]));
	                    break;
		            case "-h":
		            case "--help":
			            Help();
			            break;
		            default:
			            Help();
			            return 1;
	            }
            }
            catch (Exception e)
            {
                Console.Error.WriteLine(e.Message);
                Console.Error.WriteLine(e.StackTrace);
                return 1;
            }
            return 0;
        }
    }
}
