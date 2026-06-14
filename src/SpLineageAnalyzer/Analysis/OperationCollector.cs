using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SpLineageAnalyzer.Analysis;

internal sealed class OperationCollector : TSqlFragmentVisitor
{
    private readonly HashSet<string> _operations = new(StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyList<string> Collect(ScalarExpression expression)
    {
        var visitor = new OperationCollector();
        expression.Accept(visitor);
        visitor.CollectTokenOperations(expression);
        return visitor._operations.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public override void ExplicitVisit(SearchedCaseExpression node)
    {
        _operations.Add("CASE");
    }

    public override void ExplicitVisit(SimpleCaseExpression node)
    {
        _operations.Add("CASE");
    }

    public override void ExplicitVisit(FunctionCall node)
    {
        if (node.FunctionName is not null)
        {
            _operations.Add(node.FunctionName.Value.ToUpperInvariant());
        }
    }

    public override void ExplicitVisit(BinaryExpression node)
    {
        _operations.Add(node.BinaryExpressionType.ToString());
    }

    public override void ExplicitVisit(BooleanComparisonExpression node)
    {
        _operations.Add(node.ComparisonType.ToString());
    }

    public override void ExplicitVisit(BooleanBinaryExpression node)
    {
        _operations.Add(node.BinaryExpressionType.ToString());
    }

    public override void ExplicitVisit(InPredicate node)
    {
        _operations.Add("IN");
    }

    private void CollectTokenOperations(TSqlFragment fragment)
    {
        if (fragment.ScriptTokenStream is null ||
            fragment.FirstTokenIndex < 0 ||
            fragment.LastTokenIndex < fragment.FirstTokenIndex)
        {
            return;
        }

        var tokens = fragment.ScriptTokenStream
            .Skip(fragment.FirstTokenIndex)
            .Take(fragment.LastTokenIndex - fragment.FirstTokenIndex + 1)
            .Select(token => token.Text)
            .ToArray();

        for (var i = 0; i < tokens.Length; i++)
        {
            var token = tokens[i].Trim();
            if (string.IsNullOrWhiteSpace(token))
            {
                continue;
            }

            switch (token.ToUpperInvariant())
            {
                case "CASE":
                    _operations.Add("CASE");
                    break;
                case "IN":
                    _operations.Add("IN");
                    break;
                case "+":
                    _operations.Add("Add");
                    break;
                case "-":
                    _operations.Add("Subtract");
                    break;
                case "*":
                    _operations.Add("Multiply");
                    break;
                case "/":
                    _operations.Add("Divide");
                    break;
            }

            if (i + 1 < tokens.Length &&
                tokens[i + 1].Trim() == "(" &&
                token.All(ch => char.IsLetter(ch) || ch == '_'))
            {
                _operations.Add(token.ToUpperInvariant());
            }
        }
    }
}
