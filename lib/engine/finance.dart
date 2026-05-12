import 'dart:math' as math;

import '../models/models.dart';

class LoanOffer {
  const LoanOffer({
    required this.amountUSD,
    required this.annualInterestRate,
    required this.termYears,
  });
  final double amountUSD;
  final double annualInterestRate;
  final int termYears;
}

const loanOffers = <LoanOffer>[
  LoanOffer(amountUSD: 5000000, annualInterestRate: 0.095, termYears: 5),
  LoanOffer(amountUSD: 10000000, annualInterestRate: 0.085, termYears: 5),
  LoanOffer(amountUSD: 25000000, annualInterestRate: 0.074, termYears: 7),
  LoanOffer(amountUSD: 50000000, annualInterestRate: 0.064, termYears: 7),
  LoanOffer(amountUSD: 100000000, annualInterestRate: 0.055, termYears: 10),
  LoanOffer(amountUSD: 250000000, annualInterestRate: 0.049, termYears: 10),
  LoanOffer(amountUSD: 500000000, annualInterestRate: 0.045, termYears: 12),
];

LoanOffer? getLoanOffer(double amountUSD) {
  for (final offer in loanOffers) {
    if (offer.amountUSD == amountUSD) return offer;
  }
  return null;
}

double calculateDailyLoanPayment(
  double principalUSD,
  double annualInterestRate,
  int termYears,
) {
  final dailyRate = annualInterestRate / 365;
  final paymentCount = termYears * 365;
  if (dailyRate <= 0) return principalUSD / paymentCount;
  return principalUSD *
      (dailyRate / (1 - math.pow(1 + dailyRate, -paymentCount)));
}

double calculateDailyDebtInterest(Airline? airline) =>
    (airline?.loans ?? const <Loan>[]).fold(
      0,
      (sum, loan) => sum + (loan.principalUSD * loan.annualInterestRate) / 365,
    );

double calculateDailyDebtService(Airline? airline) =>
    (airline?.loans ?? const <Loan>[]).fold(0, (sum, loan) {
      final scheduled = loan.dailyPaymentUSD > 0
          ? loan.dailyPaymentUSD
          : calculateDailyLoanPayment(
              loan.principalUSD,
              loan.annualInterestRate,
              loan.termYears,
            );
      final interest = (loan.principalUSD * loan.annualInterestRate) / 365;
      return sum + math.min(loan.principalUSD + interest, scheduled);
    });

List<Loan> applyLoanPayment(List<Loan> loans, double paymentUSD) {
  var remaining = paymentUSD;
  final next = <Loan>[];
  for (final loan in loans) {
    if (remaining <= 0) {
      next.add(loan);
      continue;
    }
    final interest = (loan.principalUSD * loan.annualInterestRate) / 365;
    final principalPayment = math.max(
      0,
      math.min(loan.principalUSD, remaining - interest),
    );
    remaining -= interest + principalPayment;
    final principal = loan.principalUSD - principalPayment;
    if (principal > 1) {
      next.add(
        Loan(
          id: loan.id,
          principalUSD: principal,
          annualInterestRate: loan.annualInterestRate,
          termYears: loan.termYears,
          dailyPaymentUSD: loan.dailyPaymentUSD,
          issuedGameDay: loan.issuedGameDay,
        ),
      );
    }
  }
  return next;
}

List<Loan> applyLoanPrincipalPayment(
  List<Loan> loans,
  String loanId,
  double paymentUSD,
) {
  if (paymentUSD <= 0) return loans;
  return loans
      .map((loan) {
        if (loan.id != loanId) return loan;
        final principal =
            loan.principalUSD - math.min(loan.principalUSD, paymentUSD);
        if (principal <= 1) return null;
        return Loan(
          id: loan.id,
          principalUSD: principal,
          annualInterestRate: loan.annualInterestRate,
          termYears: loan.termYears,
          dailyPaymentUSD: loan.dailyPaymentUSD,
          issuedGameDay: loan.issuedGameDay,
        );
      })
      .whereType<Loan>()
      .toList();
}

String formatInterestRate(double rate) => (rate * 100).toStringAsFixed(2) + '%';
