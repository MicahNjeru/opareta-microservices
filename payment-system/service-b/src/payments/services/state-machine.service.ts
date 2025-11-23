import { Injectable, BadRequestException } from '@nestjs/common';
import { PaymentStatus } from '../entities/payment.entity';

@Injectable()
export class StateMachineService {
  private readonly allowedTransitions: Map<PaymentStatus, PaymentStatus[]> = new Map([
    [PaymentStatus.INITIATED, [PaymentStatus.PENDING]],
    [PaymentStatus.PENDING, [PaymentStatus.SUCCESS, PaymentStatus.FAILED]],
    [PaymentStatus.SUCCESS, []], // Terminal state
    [PaymentStatus.FAILED, []], // Terminal state
  ]);

  /**
   * Validate if a state transition is allowed
   * @param currentStatus Current payment status
   * @param newStatus New payment status
   * @throws BadRequestException if transition is not allowed
   */
  validateTransition(currentStatus: PaymentStatus, newStatus: PaymentStatus): void {
    // Allow staying in the same state (idempotency)
    if (currentStatus === newStatus) {
      return;
    }

    const allowedStates = this.allowedTransitions.get(currentStatus);

    if (!allowedStates || !allowedStates.includes(newStatus)) {
      throw new BadRequestException(
        `Invalid state transition: ${currentStatus} -> ${newStatus}. ` +
        `Allowed transitions from ${currentStatus}: ${allowedStates?.join(', ') || 'none (terminal state)'}`,
      );
    }
  }

  /**
   * Check if a status is a terminal state
   * @param status Payment status to check
   * @returns true if status is terminal
   */
  isTerminalState(status: PaymentStatus): boolean {
    return status === PaymentStatus.SUCCESS || status === PaymentStatus.FAILED;
  }

  /**
   * Get allowed transitions for a given status
   * @param status Current payment status
   * @returns Array of allowed next statuses
   */
  getAllowedTransitions(status: PaymentStatus): PaymentStatus[] {
    return this.allowedTransitions.get(status) || [];
  }
}