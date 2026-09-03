// Copyright (c) Pomelo Foundation. All rights reserved.
// Licensed under the MIT. See LICENSE in the project root for license information.

using Microsoft.EntityFrameworkCore.TestUtilities;
using Microsoft.EntityFrameworkCore.Update;
using Pomelo.EntityFrameworkCore.MySql.FunctionalTests.TestUtilities;

namespace Pomelo.EntityFrameworkCore.MySql.FunctionalTests;

public class ComplexCollectionJsonUpdateMySqlTest
    : ComplexCollectionJsonUpdateTestBase<ComplexCollectionJsonUpdateMySqlTest.MySqlFixture>
{
    public ComplexCollectionJsonUpdateMySqlTest(MySqlFixture fixture)
        : base(fixture)
    {
    }

    public class MySqlFixture : ComplexCollectionJsonUpdateFixtureBase
    {
        protected override ITestStoreFactory TestStoreFactory
            => MySqlTestStoreFactory.Instance;
    }
}

public class ComplexCollectionJsonUpdateMySqlNoBackslashEscapesTest
    : ComplexCollectionJsonUpdateTestBase<ComplexCollectionJsonUpdateMySqlNoBackslashEscapesTest.MySqlFixture>
{
    public ComplexCollectionJsonUpdateMySqlNoBackslashEscapesTest(MySqlFixture fixture)
        : base(fixture)
    {
    }

    public class MySqlFixture : ComplexCollectionJsonUpdateFixtureBase
    {
        protected override string StoreName
            => "ComplexCollectionJsonUpdateNoBackslashEscapesTest";

        protected override ITestStoreFactory TestStoreFactory
            => MySqlTestStoreFactory.NoBackslashEscapesInstance;
    }
}
