// Copyright (c) Pomelo Foundation. All rights reserved.
// Licensed under the MIT. See LICENSE in the project root for license information.

using System;
using System.Data;
using System.Data.Common;
using System.IO;
using System.Linq.Expressions;
using System.Reflection;
using System.Text;
using Microsoft.EntityFrameworkCore.Storage;
using MySqlConnector;

namespace Pomelo.EntityFrameworkCore.MySql.Storage.Internal
{
    /// <summary>
    /// The type mapping used by EF Core 10 when a structural type (complex type or owned entity) is mapped to a JSON column
    /// (e.g. via <c>ToJson()</c>). MySQL stores such data in a native <c>json</c> column; MariaDB exposes
    /// <c>json</c> as a <c>LONGTEXT</c> alias.
    /// </summary>
    public class MySqlStructuralJsonTypeMapping : JsonTypeMapping
    {
        private static readonly MethodInfo CreateUtf8StreamMethod
            = typeof(MySqlStructuralJsonTypeMapping).GetMethod(nameof(CreateUtf8Stream), [typeof(string)])!;

        private static readonly MethodInfo GetStringMethod
            = typeof(DbDataReader).GetRuntimeMethod(nameof(DbDataReader.GetString), [typeof(int)])!;

        public static MySqlStructuralJsonTypeMapping Default
            => JsonTypeDefault;

        public static MySqlStructuralJsonTypeMapping JsonTypeDefault { get; } = new("json");

        public virtual bool NoBackslashEscapes { get; }
        public virtual bool ReplaceLineBreaksWithCharFunction { get; }
        public virtual bool JsonDataTypeEmulation { get; }

        public MySqlStructuralJsonTypeMapping(string storeType)
            : this(
                storeType,
                noBackslashEscapes: false,
                replaceLineBreaksWithCharFunction: true,
                jsonDataTypeEmulation: false)
        {
        }

        public MySqlStructuralJsonTypeMapping(
            string storeType,
            bool noBackslashEscapes,
            bool replaceLineBreaksWithCharFunction,
            bool jsonDataTypeEmulation)
            : base(storeType, typeof(JsonTypePlaceholder), System.Data.DbType.String)
        {
            NoBackslashEscapes = noBackslashEscapes;
            ReplaceLineBreaksWithCharFunction = replaceLineBreaksWithCharFunction;
            JsonDataTypeEmulation = jsonDataTypeEmulation;
        }

        protected MySqlStructuralJsonTypeMapping(
            RelationalTypeMappingParameters parameters,
            bool noBackslashEscapes,
            bool replaceLineBreaksWithCharFunction,
            bool jsonDataTypeEmulation)
            : base(parameters)
        {
            NoBackslashEscapes = noBackslashEscapes;
            ReplaceLineBreaksWithCharFunction = replaceLineBreaksWithCharFunction;
            JsonDataTypeEmulation = jsonDataTypeEmulation;
        }

        public override MethodInfo GetDataReaderMethod()
            => GetStringMethod;

        public static MemoryStream CreateUtf8Stream(string json)
            => json == ""
                ? throw new InvalidOperationException("Cannot read a JSON value from an empty string.")
                : new MemoryStream(Encoding.UTF8.GetBytes(json));

        public override Expression CustomizeDataReaderExpression(Expression expression)
            => Expression.Call(CreateUtf8StreamMethod, expression);

        protected override string GenerateNonNullSqlLiteral(object value)
        {
            var literal = MySqlStringTypeMapping.EscapeSqlLiteralWithLineBreaks(
                (string)value,
                !NoBackslashEscapes,
                ReplaceLineBreaksWithCharFunction);

            // MySQL stores structural values in a native `json` column. MariaDB exposes JSON as a LONGTEXT alias,
            // where `CAST(... AS json)` is not valid syntax, so retain the provider's normal string literal there.
            return JsonDataTypeEmulation
                ? literal
                : $"CAST({literal} AS json)";
        }

        protected override RelationalTypeMapping Clone(RelationalTypeMappingParameters parameters)
            => new MySqlStructuralJsonTypeMapping(
                parameters,
                NoBackslashEscapes,
                ReplaceLineBreaksWithCharFunction,
                JsonDataTypeEmulation);

        protected override void ConfigureParameter(DbParameter parameter)
        {
            base.ConfigureParameter(parameter);

            if (parameter is MySqlParameter mySqlParameter)
            {
                mySqlParameter.MySqlDbType = MySqlDbType.JSON;
            }
        }
    }
}
