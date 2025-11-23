import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { StateMachineService } from './state-machine.service';
import { PaymentStatus } from '../entities/payment.entity';

describe('StateMachineService', () => {
  let service: StateMachineService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [StateMachineService],
    }).compile();

    service = module.get<StateMachineService>(StateMachineService);
  });

  describe('validateTransition', () => {
    it('should allow INITIATED -> PENDING', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.INITIATED, PaymentStatus.PENDING);
      }).not.toThrow();
    });

    it('should allow PENDING -> SUCCESS', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.PENDING, PaymentStatus.SUCCESS);
      }).not.toThrow();
    });

    it('should allow PENDING -> FAILED', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.PENDING, PaymentStatus.FAILED);
      }).not.toThrow();
    });

    it('should throw error for INITIATED -> SUCCESS', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.INITIATED, PaymentStatus.SUCCESS);
      }).toThrow(BadRequestException);
    });

    it('should throw error for INITIATED -> FAILED', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.INITIATED, PaymentStatus.FAILED);
      }).toThrow(BadRequestException);
    });

    it('should throw error for SUCCESS -> any status', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.SUCCESS, PaymentStatus.PENDING);
      }).toThrow(BadRequestException);
    });

    it('should throw error for FAILED -> any status', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.FAILED, PaymentStatus.PENDING);
      }).toThrow(BadRequestException);
    });

    it('should allow staying in the same state', () => {
      expect(() => {
        service.validateTransition(PaymentStatus.INITIATED, PaymentStatus.INITIATED);
      }).not.toThrow();

      expect(() => {
        service.validateTransition(PaymentStatus.SUCCESS, PaymentStatus.SUCCESS);
      }).not.toThrow();
    });
  });

  describe('isTerminalState', () => {
    it('should return true for SUCCESS', () => {
      expect(service.isTerminalState(PaymentStatus.SUCCESS)).toBe(true);
    });

    it('should return true for FAILED', () => {
      expect(service.isTerminalState(PaymentStatus.FAILED)).toBe(true);
    });

    it('should return false for INITIATED', () => {
      expect(service.isTerminalState(PaymentStatus.INITIATED)).toBe(false);
    });

    it('should return false for PENDING', () => {
      expect(service.isTerminalState(PaymentStatus.PENDING)).toBe(false);
    });
  });

  describe('getAllowedTransitions', () => {
    it('should return [PENDING] for INITIATED', () => {
      const transitions = service.getAllowedTransitions(PaymentStatus.INITIATED);
      expect(transitions).toEqual([PaymentStatus.PENDING]);
    });

    it('should return [SUCCESS, FAILED] for PENDING', () => {
      const transitions = service.getAllowedTransitions(PaymentStatus.PENDING);
      expect(transitions).toEqual([PaymentStatus.SUCCESS, PaymentStatus.FAILED]);
    });

    it('should return [] for SUCCESS', () => {
      const transitions = service.getAllowedTransitions(PaymentStatus.SUCCESS);
      expect(transitions).toEqual([]);
    });

    it('should return [] for FAILED', () => {
      const transitions = service.getAllowedTransitions(PaymentStatus.FAILED);
      expect(transitions).toEqual([]);
    });
  });
});