use strict;
use warnings;
use 5.014;

use Test::More tests => 6;
use Test::Differences;
use Test::MockObject;

use Data::Dumper;

require_ok('Net::Whois::Spec::Parser');

my $grammar = {
    'Simple field' => [
        { 'Domain Name' => { type => 'hostname', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional field' => [
        { 'Domain Name' => { type => 'hostname', min_occurs => 0, }, },
        { 'Referral URL' => { type => 'http url', min_occurs => 0, }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Repeatable field' => [
        { 'Domain Name' => { type => 'hostname', max_occurs => 'unbounded', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Repeatable max 2 field' => [
        { 'Domain Name' => { type => 'hostname', max_occurs => 2, }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional repeatable section' => [
        { 'A domain name' => { min_occurs => 0, max_occurs => 'unbounded', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'A domain name' => [
        { 'Domain Name' => { type => 'hostname', }, },
    ],
};

my $types = {
    'hostname' => sub {},
    'http url' => sub {},
    'roid' => sub {},
    'time stamp' => sub {},
    'key translation' => sub {},
};

sub make_mock_lexer {
    my @tokens = @_;
    my $line_no = 1;
    my $lexer = Test::MockObject->new();
    $lexer->mock('peek_line', sub {
            if (exists $tokens[$line_no - 1]) {
                return @{ $tokens[$line_no - 1] };
            }
            else {
                return;
            }
            });
    $lexer->mock('line_no', sub {
            return $line_no;
            });
    $lexer->mock('next_line', sub {
            $line_no++;
            return
            });
}

subtest 'Simple line' => sub {
    plan tests => 2;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Simple field' );
        eq_or_diff $result, [], 'Should accept field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['non-empty line', []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Simple field' );
        is scalar(@$result), 1, 'Should reject non-field line';
    }
};

subtest 'Optional subrule' => sub {
    plan tests => 3;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Optional field' );
        eq_or_diff $result, [], 'Should accept omitted field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Optional field' );
        eq_or_diff $result, [], 'Should accept empty field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], undef], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Optional field' );
        is scalar(@$result), 1, 'Should reject mixed empty field syntaxes';
    }
};

subtest 'Repeatable subrule' => sub {
    plan tests => 3;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN3.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Repeatable field' );
        eq_or_diff $result, [], 'Should accept repeated field lines';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Repeatable max 2 field' );
        eq_or_diff $result, [], 'Should accept repeated field lines';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN3.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Repeatable max 2 field' );
        is scalar(@$result), 1, 'Should reject too many repetitions of field lines';
    }

};

subtest 'Error propagation' => sub {
    plan tests => 1;

    my $lexer = make_mock_lexer (
        ['field', ['Domain Name', [], 'DOMAIN.EXAMPLE'], ['BOOM!']],
        ['EOF', undef, []],
    );
    my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
    my $result = $parser->parse_output( 'Simple field' );
    eq_or_diff $result, ['BOOM!'], 'Should propagate errors from lexer';
};

subtest 'Optional repeatable subrule' => sub {
    plan tests => 1;

    {
        my $lexer = make_mock_lexer (
            ['EOF', undef, []],
        );
        my $parser = Net::Whois::Spec::Parser->new(lexer => $lexer, grammar => $grammar, types => $types);
        my $result = $parser->parse_output( 'Optional repeatable section' );
        eq_or_diff $result, [], 'Should accept omitted lines';
    }

};
