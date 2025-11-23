import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Inject,
  LoggerService,
} from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { Cache } from 'cache-manager';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { firstValueFrom } from 'rxjs';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
    @Inject(CACHE_MANAGER) private cacheManager: Cache,
    @Inject(WINSTON_MODULE_NEST_PROVIDER)
    private readonly logger: LoggerService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const token = this.extractTokenFromHeader(request);

    if (!token) {
      this.logger.warn('No token provided in request');
      throw new UnauthorizedException('No token provided');
    }

    // Check cache first
    const cacheKey = `token:${token}`;
    const cachedValidation = await this.cacheManager.get<any>(cacheKey);

    if (cachedValidation) {
      this.logger.log('Token validation retrieved from cache');
      if (!cachedValidation.valid) {
        throw new UnauthorizedException('Invalid token');
      }
      request.user = cachedValidation.user;
      return true;
    }

    // Validate token with Service A
    try {
      const authServiceUrl = this.configService.get<string>('AUTH_SERVICE_URL');
      const response = await firstValueFrom(
        this.httpService.post(`${authServiceUrl}/auth/validate`, { token }),
      );

      const validationResult = response.data;

      // Cache the validation result
      const cacheTTL = this.configService.get<number>('CACHE_TTL') || 300;
      await this.cacheManager.set(cacheKey, validationResult, cacheTTL * 1000);

      if (!validationResult.valid) {
        this.logger.warn('Token validation failed');
        throw new UnauthorizedException('Invalid token');
      }

      // Attach user info to request
      request.user = validationResult.user;
      this.logger.log(`Token validated successfully for user: ${validationResult.user.id}`);

      return true;
    } catch (error) {
      this.logger.error(`Token validation error: ${error.message}`);
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Failed to validate token');
    }
  }

  private extractTokenFromHeader(request: any): string | undefined {
    const authHeader = request.headers.authorization;
    if (!authHeader) {
      return undefined;
    }

    const [type, token] = authHeader.split(' ');
    return type === 'Bearer' ? token : undefined;
  }
}