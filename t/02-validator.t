use strict;
use warnings;
use 5.014;

use Test::More tests => 9;
use Test::Differences;
use Test::MockObject;

require_ok('PDT::TS::Whois::Validator');
use PDT::TS::Whois::Validator qw( validate );

my $grammar = {
    'Simple field' => [
        { 'Domain Name' => { type => 'hostname', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional-constrained field' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', quantifier => 'optional-constrained', }, },
        { 'Referral URL' => { line => 'field', type => 'http url', quantifier => 'optional-constrained', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional-free field' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', quantifier => 'optional-constrained', }, },
        { 'Referral URL' => { line => 'field', type => 'http url', quantifier => 'optional-free', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Repeatable field' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', quantifier => 'repeatable', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Repeatable max 2 field' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', quantifier => 'repeatable max 2', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional repeatable section' => [
        { 'A domain name' => { quantifier => 'optional-repeatable', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Optional repeatable field' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', quantifier => 'optional-repeatable', }, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'A domain name' => [
        { 'Domain Name' => { line => 'field', type => 'hostname', }, },
    ],
    'Repeated choice section' => [
        { 'Domain or referral' => {}, },
        { 'Domain or referral' => {}, },
        { 'EOF' => { line => 'EOF', }, },
    ],
    'Domain or referral' => {
        'Domain Name' => { line => 'field', type => 'hostname', },
        'Referral URL' => { line => 'field', type => 'http url', },
    },
    'Anything' => [
        { 'Any line' => { line => 'any line', quantifier => 'repeatable' }, },
    ],
};

sub mock_validate_type {
    my $value = shift;
    if ($value && $value eq 'INVALID!') {
        return 'validation error';
    }
    else {
        return ();
    }
}

my %type_subs = (
    'hostname' => \&mock_validate_type,
    'http url' => \&mock_validate_type,
    'roid' => \&mock_validate_type,
    'time stamp' => \&mock_validate_type,
    'key translation' => \&mock_validate_type,
    'query domain name' => \&mock_validate_type,
);

my $types = Test::MockObject->new();
$types->mock('has_type', sub {
    my $self = shift;
    my $type_name = shift;
    return exists $type_subs{$type_name};
});
$types->mock('validate_type', sub {
    my $self = shift;
    my $type_name = shift;
    my $value = shift;
    return $type_subs{$type_name}($value);
});


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
            $line_no++ if $line_no < @tokens;
            return
            });
}

subtest 'Simple line' => sub {
    plan tests => 3;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Simple field', lexer => $lexer, grammar => $grammar, types => $types);
        eq_or_diff \@errors, [], 'Should accept field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['non-empty line', 'gibberish', []],
            ['EOF', undef, []],
        );
        my @errors = validate(rule => 'Simple field', lexer => $lexer, grammar => $grammar, types => $types);
        cmp_ok scalar(@errors), '>=', 1, 'Should reject non-field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Simple field', lexer => $lexer, grammar => $grammar, types => $types);
        cmp_ok scalar(@errors), '>=', 1, 'Should reject empty-field line';
    }
};

subtest 'Optional-free subrule' => sub {
    plan tests => 3;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-free field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept omitted field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-free field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept empty field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], undef], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-free field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept mixed empty field syntaxes';
    }
};

subtest 'Optional-constrained subrule' => sub {
    plan tests => 6;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-constrained field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept omitted field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['field', ['Referral URL', [], 'http://domain.example/'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-constrained field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept empty field line';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Referral URL', [], undef], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-constrained field', lexer => $lexer, grammar => $grammar, types => $types );
        cmp_ok scalar(@errors), '>=', 1, 'Should reject mixed empty field syntaxes';
        like $errors[0], qr/line 1/, 'Should refer to line number of the empty field';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional-constrained field', lexer => $lexer, grammar => $grammar, types => $types );
        cmp_ok scalar(@errors), '>=', 1, 'Should reject mixed empty field syntaxes';
        like $errors[0], qr/line 2/, 'Should refer to line number where empty field was expected';
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
        my @errors = validate( rule => 'Repeatable field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept repeated field lines';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Repeatable max 2 field', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept repeated field lines';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN3.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Repeatable max 2 field', lexer => $lexer, grammar => $grammar, types => $types );
        ok scalar(@errors), 'Should reject too many repetitions of field lines';
    }

};

subtest 'Error propagation' => sub {
    plan tests => 1;

    my $lexer = make_mock_lexer (
        ['field', ['Domain Name', [], 'DOMAIN.EXAMPLE'], ['BOOM!']],
        ['EOF', undef, []],
    );
    my @errors = validate( rule => 'Simple field', lexer => $lexer, grammar => $grammar, types => $types );
    eq_or_diff \@errors, ['BOOM!'], 'Should propagate errors from lexer';
};

subtest 'Optional repeatable subrule' => sub {
    plan tests => 3;

    {
        my $lexer = make_mock_lexer (
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional repeatable section', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept omitted lines';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], undef], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional repeatable field', lexer => $lexer, grammar => $grammar, types => $types );
        cmp_ok scalar(@errors), '>=', 1, 'Should reject empty field in repetition';
    }

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], undef], []],
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Optional repeatable field', lexer => $lexer, grammar => $grammar, types => $types );
        cmp_ok scalar(@errors), '>=', 1, 'Should reject empty field at start of repetition';
    }

};

subtest 'Repeated choice section' => sub {
    plan tests => 1;

    {
        my $lexer = make_mock_lexer (
            ['field', ['Domain Name', [], 'DOMAIN1.EXAMPLE'], []],
            ['field', ['Domain Name', [], 'DOMAIN2.EXAMPLE'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Repeated choice section', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept repeated choice section';
    }

};

subtest 'Anything' => sub {
    plan tests => 1;

    {
        my $lexer = make_mock_lexer (
            ['empty line', undef, []],
            ['non-empty line', 'gibberish', []],
            ['roid line', ['INVALID!', 'INVALID!'], []],
            ['EOF', undef, []],
        );
        my @errors = validate( rule => 'Anything', lexer => $lexer, grammar => $grammar, types => $types );
        eq_or_diff \@errors, [], 'Should accept anything';
    }

};
