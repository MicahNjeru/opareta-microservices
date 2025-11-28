import { Test, TestingModule } from '@nestjs/testing';
import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { of, throwError } from 'rxjs';
import { AuthGuard } from './auth.guard';

describe('AuthGuard', () => {
  let guard: AuthGuard;
  let httpService: HttpService;
  let cacheManager: any;

  const mockHttpService = {
    post: jest.fn(),
  };

  const mockConfigService = {
    get: jest.fn((key: string) => {
      if (key === 'AUTH_SERVICE_URL') return 'http://localhost:3001';
      if (key === 'CACHE_TTL') return 300;
      return null;
    }),
  };

  const mockCacheManager = {
    get: jest.fn(),
    set: jest.fn(),
  };

  const mockLogger = {
    log: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthGuard,
        {
          provide: HttpService,
          useValue: mockHttpService,
        },
        {
          provide: ConfigService,
          useValue: mockConfigService,
        },
        {
          provide: CACHE_MANAGER,
          useValue: mockCacheManager,
        },
        {
          provide: WINSTON_MODULE_NEST_PROVIDER,
          useValue: mockLogger,
        },
      ],
    }).compile();

    guard = module.get<AuthGuard>(AuthGuard);
    httpService = module.get<HttpService>(HttpService);
    cacheManager = module.get(CACHE_MANAGER);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  const createMockContext = (token?: string): ExecutionContext => {
    return {
      switchToHttp: () => ({
        getRequest: () => ({
          headers: {
            authorization: token ? `Bearer ${token}` : undefined,
          },
        }),
      }),
    } as ExecutionContext;
  };

  describe('canActivate', () => {
    it('should throw UnauthorizedException if no token provided', async () => {
      const context = createMockContext();

      await expect(guard.canActivate(context)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('should return true for valid token from cache', async () => {
      const mockValidation = {
        valid: true,
        user: { id: '123', phone_number: '+256700000000' },
      };

      mockCacheManager.get.mockResolvedValue(mockValidation);

      const context = createMockContext('valid-token');
      const result = await guard.canActivate(context);

      expect(result).toBe(true);
      expect(mockHttpService.post).not.toHaveBeenCalled();
    });

    it('should validate token with Service A if not cached', async () => {
      const mockValidation = {
        valid: true,
        user: { id: '123', phone_number: '+256700000000' },
      };

      mockCacheManager.get.mockResolvedValue(null);
      mockHttpService.post.mockReturnValue(of({ data: mockValidation }));

      const context = createMockContext('valid-token');
      const result = await guard.canActivate(context);

      expect(result).toBe(true);
      expect(mockHttpService.post).toHaveBeenCalledWith(
        'http://localhost:3001/auth/validate',
        { token: 'valid-token' },
      );
      expect(mockCacheManager.set).toHaveBeenCalled();
    });

    it('should throw UnauthorizedException for invalid token', async () => {
      const mockValidation = {
        valid: false,
        message: 'Invalid token',
      };

      mockCacheManager.get.mockResolvedValue(null);
      mockHttpService.post.mockReturnValue(of({ data: mockValidation }));

      const context = createMockContext('invalid-token');

      await expect(guard.canActivate(context)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('should throw UnauthorizedException if validation service fails', async () => {
      mockCacheManager.get.mockResolvedValue(null);
      mockHttpService.post.mockReturnValue(
        throwError(() => new Error('Service unavailable')),
      );

      const context = createMockContext('some-token');

      await expect(guard.canActivate(context)).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });
});