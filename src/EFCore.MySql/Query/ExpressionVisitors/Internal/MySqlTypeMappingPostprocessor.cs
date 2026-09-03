// Copyright (c) Pomelo Foundation. All rights reserved.
// Licensed under the MIT. See LICENSE in the project root for license information.

using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore.Query;
using Microsoft.EntityFrameworkCore.Query.SqlExpressions;
using Microsoft.EntityFrameworkCore.Storage;
using Pomelo.EntityFrameworkCore.MySql.Query.ExpressionTranslators.Internal;

namespace Pomelo.EntityFrameworkCore.MySql.Query.ExpressionVisitors.Internal;

/// <summary>
///     Applies the inferred element mapping to parameter-backed JSON_TABLE() expressions.
/// </summary>
public class MySqlTypeMappingPostprocessor : RelationalTypeMappingPostprocessor
{
    public MySqlTypeMappingPostprocessor(
        QueryTranslationPostprocessorDependencies dependencies,
        RelationalQueryTranslationPostprocessorDependencies relationalDependencies,
        RelationalQueryCompilationContext queryCompilationContext)
        : base(dependencies, relationalDependencies, queryCompilationContext)
    {
    }

    protected override Expression VisitExtension(Expression extensionExpression)
        => extensionExpression is MySqlJsonTableExpression jsonTableExpression
           && jsonTableExpression.JsonExpression is SqlParameterExpression { TypeMapping: null } parameterExpression
           && TryGetInferredTypeMapping(jsonTableExpression.Alias, "value", out var elementTypeMapping)
            ? ApplyTypeMappingsOnJsonTableExpression(jsonTableExpression, parameterExpression, elementTypeMapping)
            : base.VisitExtension(extensionExpression);

    protected virtual MySqlJsonTableExpression ApplyTypeMappingsOnJsonTableExpression(
        MySqlJsonTableExpression jsonTableExpression,
        SqlParameterExpression parameterExpression,
        RelationalTypeMapping elementTypeMapping)
    {
        var parameterTypeMapping = RelationalDependencies.TypeMappingSource.FindMapping(
            parameterExpression.Type,
            QueryCompilationContext.Model,
            elementTypeMapping);

        if (parameterTypeMapping?.ElementTypeMapping is null)
        {
            return jsonTableExpression;
        }

        var columnInfo = new MySqlJsonTableExpression.ColumnInfo(
            "value",
            elementTypeMapping,
            new[]
            {
                new PathSegment(
                    RelationalDependencies.SqlExpressionFactory.Constant(
                        0,
                        RelationalDependencies.TypeMappingSource.FindMapping(typeof(int))))
            });

        return jsonTableExpression.Update(
            parameterExpression.ApplyTypeMapping(parameterTypeMapping),
            jsonTableExpression.Path,
            new[] { columnInfo });
    }
}
